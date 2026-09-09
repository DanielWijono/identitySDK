import Foundation

/// One active run per client. Public progress is coalesced and never contains credentials or images.
public actor VerificationClient {
    private struct Run {
        let generation: UUID
        let deadline: Duration
        let session: VerificationSession
        let evidence: any EvidenceSource
        let continuation: CheckedContinuation<VerificationOutcome, any Error>
        let progress: AsyncStream<VerificationProgress>.Continuation?
        var worker: Task<Void, Never>?
        var expiry: Task<Void, Never>?
        var finishing = false
    }
    private let provider: any VerificationProvider
    private let clock: any SessionClock
    private var active: Run?
    private struct PendingCleanup {
        let evidence: any EvidenceSource
        let result: Result<VerificationOutcome, any Error>
    }
    private var pendingCleanup: PendingCleanup?
    private var retryingCleanup = false

    public var requiresCleanup: Bool { pendingCleanup != nil }

    /// Retry only local deletion, never uploads or submission. After successful cleanup, delivers
    /// the originally reserved outcome (or throws the original technical failure).
    public func retryCleanup() async throws -> VerificationOutcome {
        guard !retryingCleanup else { throw VerificationError.cleanupInProgress }
        guard let pendingCleanup else { throw VerificationError.noCleanupPending }
        retryingCleanup = true
        defer { retryingCleanup = false }
        let evidence = pendingCleanup.evidence
        do { try await Task { try await evidence.cleanup() }.value }
        catch { throw VerificationError.cleanupRequired }
        self.pendingCleanup = nil
        return try pendingCleanup.result.get()
    }

    public init(provider: any VerificationProvider) {
        self.provider = provider
        self.clock = SystemSessionClock()
    }

    init(provider: any VerificationProvider, clock: any SessionClock) {
        self.provider = provider
        self.clock = clock
    }

    /// Call after the user explicitly accepts the disclosure. Acknowledgement precedes capture/upload.
    /// The optional stream must be created with bufferingNewest(1) by the caller.
    public func run(
        session: VerificationSession,
        consent: Consent,
        evidence: any EvidenceSource,
        progress: AsyncStream<VerificationProgress>.Continuation? = nil
    ) async throws -> VerificationOutcome {
        guard active == nil else { throw VerificationError.sessionAlreadyActive }
        guard pendingCleanup == nil else { throw VerificationError.cleanupRequired }
        guard !session.id.isEmpty, !session.token.isEmpty, !consent.disclosureVersion.isEmpty else {
            throw VerificationError.invalidSession
        }
        let lifetime = min(session.expiresAt.timeIntervalSince(clock.wallNow), 15 * 60)
        guard lifetime > 0 else { throw VerificationError.expired }
        let generation = UUID()
        let deadline = clock.elapsed + .seconds(lifetime)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                active = Run(generation: generation, deadline: deadline, session: session, evidence: evidence,
                             continuation: continuation, progress: progress)
                if Task.isCancelled {
                    Task { await self.finish(generation, result: .success(.cancelled), remoteCancel: true) }
                    return
                }
                active?.worker = Task { await self.execute(generation, session: session, consent: consent, evidence: evidence) }
                active?.expiry = Task {
                    do { try await self.clock.sleep(until: deadline) } catch { return }
                    await self.finish(generation, result: .failure(VerificationError.expired), remoteCancel: true)
                }
            }
        } onCancel: {
            Task { await self.finish(generation, result: .success(.cancelled), remoteCancel: true) }
        }
    }

    public func cancel() async {
        guard let active else { return }
        await finish(active.generation, result: .success(.cancelled), remoteCancel: true)
    }

    private func advance(_ generation: UUID, to progress: VerificationProgress) throws {
        guard let active, active.generation == generation, !active.finishing else { throw CancellationError() }
        try Task.checkCancellation()
        guard active.session.expiresAt > clock.wallNow, clock.elapsed < active.deadline else {
            throw VerificationError.expired
        }
        active.progress?.yield(progress)
    }

    private func execute(_ generation: UUID, session: VerificationSession, consent: Consent, evidence: any EvidenceSource) async {
        do {
            try advance(generation, to: .consent)
            try await provider.acknowledgeConsent(consent, session: session)
            // Capture both sides before transferring any evidence.
            var confirmed: [Evidence] = []
            for side in DocumentSide.allCases {
                try advance(generation, to: .capture(side))
                let item: Evidence
                do { item = try await evidence.confirmedEvidence(for: side) }
                catch { throw VerificationError.evidenceFailure }
                guard item.side == side else { throw VerificationError.evidenceFailure }
                confirmed.append(item)
            }
            for item in confirmed {
                try advance(generation, to: .upload(item.side))
                try await provider.upload(item, session: session)
            }
            try advance(generation, to: .submit)
            try await provider.submit(session: session, idempotencyKey: generation)
            try advance(generation, to: .awaitDecision)
            let outcome = try await provider.decision(session: session)
            try advance(generation, to: .awaitDecision)
            await finish(generation, result: .success(outcome))
        } catch {
            let safeError = (error as? VerificationError) ?? .providerFailure
            await finish(generation, result: .failure(safeError), remoteCancel: true)
        }
    }

    private func finish(_ generation: UUID, result: Result<VerificationOutcome, any Error>, remoteCancel: Bool = false) async {
        guard var run = active, run.generation == generation, !run.finishing else { return }
        run.finishing = true
        active = run // Reserve the terminal transition before cleanup suspends.
        run.worker?.cancel()
        run.expiry?.cancel()
        // Independent task: cleanup must not inherit the worker's cancelled status.
        let evidence = run.evidence
        let delivered: Result<VerificationOutcome, any Error>
        do {
            try await Task { try await evidence.cleanup() }.value
            delivered = result
        } catch {
            pendingCleanup = PendingCleanup(evidence: evidence, result: result)
            delivered = .failure(VerificationError.cleanupRequired)
        }
        run.progress?.yield(.finished)
        run.progress?.finish()
        active = nil
        run.continuation.resume(with: delivered)
        if remoteCancel {
            let provider = self.provider
            let session = run.session
            Task { await provider.cancel(session: session) }
        }
    }
}
