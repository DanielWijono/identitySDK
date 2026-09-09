import Foundation
import Synchronization
import Testing
@testable import IdentityFlowCore
import IdentityFlowDemoSupport

@available(macOS 15, iOS 18, *)
private final class ManualClock: SessionClock, Sendable {
    private struct State {
        var wall = Date(timeIntervalSince1970: 1_000)
        var elapsed: Duration = .zero
        var waiters: [UUID: (Duration, CheckedContinuation<Void, any Error>)] = [:]
        var cancelled: Set<UUID> = []
    }
    private let state = Mutex(State())
    var wallNow: Date { state.withLock { $0.wall } }
    var elapsed: Duration { state.withLock { $0.elapsed } }
    func waitForSleeper() async {
        while state.withLock({ $0.waiters.isEmpty }) { await Task.yield() }
    }
    func advance(seconds: Double, wallSeconds: Double? = nil, wakeSleepers: Bool = true) {
        let ready = state.withLock { state in
            state.elapsed += .seconds(seconds)
            state.wall.addTimeInterval(wallSeconds ?? seconds)
            let ready = state.waiters.filter { wakeSleepers && $0.value.0 <= state.elapsed }
            for id in ready.keys { state.waiters.removeValue(forKey: id) }
            return ready.map { $0.value.1 }
        }
        for continuation in ready { continuation.resume() }
    }
    func sleep(until deadline: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                state.withLock { state in
                    if state.cancelled.remove(id) != nil { continuation.resume(throwing: CancellationError()) }
                    else if state.elapsed >= deadline { continuation.resume() }
                    else { state.waiters[id] = (deadline, continuation) }
                }
            }
        } onCancel: {
            self.state.withLock { state in
                if let entry = state.waiters.removeValue(forKey: id) { entry.1.resume(throwing: CancellationError()) }
                else { state.cancelled.insert(id) }
            }
        }
    }
}

private enum Boundary: CaseIterable, Sendable {
    case consent, frontCapture, backCapture, frontUpload, backUpload, submit, decision
}

/// Explicit handshakes avoid timing sleeps when positioning cancellation.
private actor Barrier {
    private var arrived = false
    private var released = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func hold() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            arrived = true
            for observer in observers { observer.resume() }
            observers.removeAll()
        }
    }
    func waitForArrival() async {
        if arrived { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { released = true; releaseContinuation?.resume(); releaseContinuation = nil }
}

private actor Harness: VerificationProvider, EvidenceSource {
    let boundary: Boundary
    let barrier = Barrier()
    let cleanupBarrier: Barrier?
    var operations: [Boundary] = []
    var cleanupCount = 0
    private let source = SyntheticEvidenceSource()
    init(_ boundary: Boundary, cleanupBarrier: Barrier? = nil) {
        self.boundary = boundary; self.cleanupBarrier = cleanupBarrier
    }
    private func visit(_ operation: Boundary) async {
        operations.append(operation)
        if operation == boundary { await barrier.hold() }
    }
    func acknowledgeConsent(_ consent: Consent, session: VerificationSession) async { await visit(.consent) }
    func confirmedEvidence(for side: DocumentSide) async throws -> Evidence {
        // Obtain before holding to simulate capture returning data after cancellation.
        let evidence = try await source.confirmedEvidence(for: side)
        await visit(side == .front ? .frontCapture : .backCapture)
        return evidence
    }
    func upload(_ evidence: Evidence, session: VerificationSession) async {
        await visit(evidence.side == .front ? .frontUpload : .backUpload)
    }
    func submit(session: VerificationSession, idempotencyKey: UUID) async { await visit(.submit) }
    func decision(session: VerificationSession) async -> VerificationOutcome {
        await visit(.decision)
        return .approved(.init(sessionID: session.id, providerReference: "synthetic"))
    }
    func cancel(session: VerificationSession) {}
    func cleanup() async {
        cleanupCount += 1
        await source.cleanup()
        if let cleanupBarrier { await cleanupBarrier.hold() }
    }
}

private func testSession(expiresAt: Date = Date().addingTimeInterval(60)) -> VerificationSession {
    .init(id: "test", token: "synthetic", expiresAt: expiresAt)
}
private let accepted = Consent(disclosureVersion: "synthetic-v1")

@Test(arguments: Boundary.allCases)
private func cancellationAtEveryBoundary(boundary: Boundary) async throws {
    let harness = Harness(boundary)
    let client = VerificationClient(provider: harness)
    let (stream, progress) = AsyncStream<VerificationProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let run = Task { try await client.run(session: testSession(), consent: accepted, evidence: harness, progress: progress) }
    await harness.barrier.waitForArrival()
    await client.cancel()
    #expect(try await run.value == .cancelled)
    #expect(await harness.cleanupCount == 1)
    var terminalSnapshots: [VerificationProgress] = []
    for await snapshot in stream { terminalSnapshots.append(snapshot) }
    #expect(terminalSnapshots == [.finished])
    await harness.barrier.release()
}

@available(macOS 15, iOS 18, *)
@Test private func monotonicDeadlineSurvivesWallClockRollback() async {
    let clock = ManualClock()
    let harness = Harness(.consent)
    let client = VerificationClient(provider: harness, clock: clock)
    let session = testSession(expiresAt: clock.wallNow.addingTimeInterval(60))
    let run = Task { try await client.run(session: session, consent: accepted, evidence: harness) }
    await harness.barrier.waitForArrival()
    clock.advance(seconds: 60, wallSeconds: -3_600)
    await #expect(throws: VerificationError.expired) { try await run.value }
    #expect(await harness.cleanupCount == 1)
    await harness.barrier.release()
}

@available(macOS 15, iOS 18, *)
@Test private func operationBoundaryEnforcesDeadlineBeforeTimerRuns() async {
    let clock = ManualClock()
    let harness = Harness(.consent)
    let client = VerificationClient(provider: harness, clock: clock)
    let run = Task {
        try await client.run(session: testSession(expiresAt: clock.wallNow.addingTimeInterval(60)),
                             consent: accepted, evidence: harness)
    }
    await harness.barrier.waitForArrival()
    await clock.waitForSleeper()
    clock.advance(seconds: 60, wallSeconds: -3_600, wakeSleepers: false)
    await harness.barrier.release()
    await #expect(throws: VerificationError.expired) { try await run.value }
    #expect(await harness.operations == [.consent])
}

@available(macOS 15, iOS 18, *)
@Test private func localCeilingExpiresLongBackendSession() async {
    let clock = ManualClock()
    let harness = Harness(.decision)
    let client = VerificationClient(provider: harness, clock: clock)
    let session = testSession(expiresAt: clock.wallNow.addingTimeInterval(3_600))
    let run = Task { try await client.run(session: session, consent: accepted, evidence: harness) }
    await harness.barrier.waitForArrival()
    clock.advance(seconds: 900)
    await #expect(throws: VerificationError.expired) { try await run.value }
    await harness.barrier.release()
}

@Test private func finishingReservesClientUntilCleanupCompletes() async throws {
    let cleanup = Barrier()
    let harness = Harness(.decision, cleanupBarrier: cleanup)
    let client = VerificationClient(provider: harness)
    let run = Task { try await client.run(session: testSession(), consent: accepted, evidence: harness) }
    await harness.barrier.waitForArrival()
    await harness.barrier.release()
    await cleanup.waitForArrival() // Approval has reserved the terminal transition.
    await client.cancel() // Must not replace the already reserved approval.
    await #expect(throws: VerificationError.sessionAlreadyActive) {
        try await client.run(session: testSession(), consent: accepted, evidence: SyntheticEvidenceSource())
    }
    await cleanup.release()
    #expect(try await run.value == .approved(.init(sessionID: "test", providerReference: "synthetic")))
    #expect(await harness.cleanupCount == 1)
    // A completed client can accept a fresh run.
    let second = try await client.run(session: testSession(), consent: accepted, evidence: SyntheticEvidenceSource())
    #expect(second == .approved(.init(sessionID: "test", providerReference: "synthetic")))
}
