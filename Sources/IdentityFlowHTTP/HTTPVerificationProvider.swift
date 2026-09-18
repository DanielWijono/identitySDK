import Foundation
import CryptoKit
import IdentityFlowCore

/// Provider adapter for the demo HTTP contract.
///
/// One instance per logical run: it remembers the evidence IDs it uploaded so the commit can name
/// them, and the provider reference the server assigned.
///
/// Every mutation is reconciled rather than blindly repeated. A transport failure is ambiguous —
/// the server may already have applied the change — so the adapter asks for authoritative state
/// before deciding whether to send again. That is what keeps a lost response from producing a
/// second logical submission.
public actor HTTPVerificationProvider: VerificationProvider {
    public struct Configuration: Sendable {
        public var retry: RetryPolicy
        /// Foreground observation budget. When it elapses the run hands off as pending.
        public var decisionBudget: Duration
        public var initialPollInterval: Duration
        public var maxPollInterval: Duration

        public init(retry: RetryPolicy = RetryPolicy(),
                    decisionBudget: Duration = .seconds(30),
                    initialPollInterval: Duration = .seconds(1),
                    maxPollInterval: Duration = .seconds(5)) {
            self.retry = retry
            self.decisionBudget = decisionBudget
            self.initialPollInterval = initialPollInterval
            self.maxPollInterval = maxPollInterval
        }
    }

    private let transport: any HTTPTransport
    private let configuration: Configuration
    private let clock: any ProviderClock
    private var evidenceIDs: [DocumentSide: UUID] = [:]
    private var reference: String?

    public init(transport: any HTTPTransport,
                configuration: Configuration = Configuration(),
                clock: any ProviderClock = SystemProviderClock()) {
        self.transport = transport
        self.configuration = configuration
        self.clock = clock
    }

    // MARK: - VerificationProvider

    public func acknowledgeConsent(_ consent: Consent, session: VerificationSession) async throws {
        let body = Wire.encode(ConsentBody(disclosureVersion: consent.disclosureVersion))
        let request = HTTPRequest(method: "PUT", path: "/sessions/\(session.id)/consent",
                                  headers: authorized(session, contentType: "application/json"), body: body)
        // Re-sending the same disclosure version is idempotent by contract, so the reconciliation
        // step only has to confirm the server moved past consent.
        _ = try await perform(request, session: session) { state in
            state.state != .awaitingConsent
        }
    }

    public func upload(_ evidence: Evidence, session: VerificationSession) async throws {
        let bytes = try await evidence.reader.read()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        evidenceIDs[evidence.side] = evidence.id
        var headers = authorized(session, contentType: "image/jpeg")
        headers[Wire.headerEvidenceID] = evidence.id.uuidString
        headers[Wire.headerEvidenceDigest] = digest
        let request = HTTPRequest(method: "PUT",
                                  path: "/sessions/\(session.id)/evidence/\(evidence.side.rawValue)",
                                  headers: headers, body: bytes)
        let id = evidence.id, side = evidence.side
        _ = try await perform(request, session: session) { state in
            // Only our own evidence ID counts as applied; a superseded upload must be repeated.
            state.receivedEvidence[side.rawValue] == id
        }
    }

    public func submit(session: VerificationSession, idempotencyKey: UUID) async throws {
        guard let front = evidenceIDs[.front], let back = evidenceIDs[.back] else {
            throw VerificationError.evidenceFailure
        }
        var headers = authorized(session, contentType: "application/json")
        headers[Wire.headerIdempotencyKey] = idempotencyKey.uuidString
        let body = Wire.encode(SubmissionBody(frontEvidenceID: front, backEvidenceID: back))
        let request = HTTPRequest(method: "POST", path: "/sessions/\(session.id)/submission",
                                  headers: headers, body: body)
        let response = try await perform(request, session: session) { state in
            // The commit landed only if the server is holding *this* run's key.
            state.submissionKey == idempotencyKey
        }
        if let accepted = try? Wire.decoder.decode(SubmissionAccepted.self, from: response.body) {
            reference = accepted.reference
        } else if reference == nil {
            // Reconciliation confirmed the commit without replaying the original 202 body.
            reference = try await state(for: session).reference
        }
    }

    public func decision(session: VerificationSession) async throws -> VerificationOutcome {
        let deadline = clock.now.addingTimeInterval(configuration.decisionBudget.seconds)
        var interval = configuration.initialPollInterval
        while true {
            try Task.checkCancellation()
            let state = try await self.state(for: session)
            if let reference = state.reference { self.reference = reference }
            let handle = VerificationReference(sessionID: session.id,
                                               providerReference: reference ?? state.reference ?? "")
            switch state.state {
            case .approved: return .approved(handle)
            case .rejected: return .rejected(handle)
            case .cancelled: return .cancelled
            case .expired: throw VerificationError.expired
            case .awaitingConsent, .awaitingEvidence:
                // The server disagrees that we committed; repeating the workflow is not this
                // adapter's decision to make.
                throw VerificationError.providerFailure
            case .submitted:
                // Hand off rather than block the UI. The host resolves the decision out of band.
                guard clock.now < deadline else { return .pending(handle) }
                try await clock.sleep(for: interval)
                interval = min(interval * 2, configuration.maxPollInterval)
            }
        }
    }

    public func cancel(session: VerificationSession) async {
        // Best effort and idempotent. A failure here must never mask the local terminal result.
        let request = HTTPRequest(method: "POST", path: "/sessions/\(session.id)/cancel",
                                  headers: authorized(session))
        _ = try? await transport.send(request)
    }

    // MARK: - Transport

    private func authorized(_ session: VerificationSession, contentType: String? = nil) -> [String: String] {
        var headers = ["Authorization": "Bearer \(session.token)", "Accept": "application/json"]
        if let contentType { headers["Content-Type"] = contentType }
        return headers
    }

    private func state(for session: VerificationSession) async throws -> SessionStateBody {
        let request = HTTPRequest(method: "GET", path: "/sessions/\(session.id)",
                                  headers: authorized(session))
        let response = try await send(request)
        guard (200..<300).contains(response.status) else {
            throw VerificationError.from(status: response.status, code: code(of: response))
        }
        guard let body = try? Wire.decoder.decode(SessionStateBody.self, from: response.body) else {
            throw VerificationError.providerFailure
        }
        return body
    }

    private func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try Task.checkCancellation()
        return try await transport.send(request)
    }

    private func code(of response: HTTPResponse) -> String? {
        try? Wire.decoder.decode(ErrorBody.self, from: response.body).code
    }

    /// Sends `request`, retrying only transient failures inside the session budget.
    ///
    /// `wasApplied` inspects authoritative server state after an ambiguous or transient failure.
    /// When it reports the mutation already landed, the request is not sent again.
    private func perform(_ request: HTTPRequest,
                         session: VerificationSession,
                         wasApplied: @Sendable (SessionStateBody) -> Bool) async throws -> HTTPResponse {
        var attempt = 0
        var lastRetryAfter: String?
        while true {
            try Task.checkCancellation()
            guard session.expiresAt > clock.now else { throw VerificationError.expired }

            var transportFailed = false
            do {
                let response = try await send(request)
                if (200..<300).contains(response.status) { return response }
                guard RetryPolicy.isRetryable(status: response.status) else {
                    throw VerificationError.from(status: response.status, code: code(of: response))
                }
                lastRetryAfter = response.header(Wire.headerRetryAfter)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as VerificationError {
                throw error
            } catch {
                // Ambiguous: the server may have applied this mutation before the failure.
                transportFailed = true
                lastRetryAfter = nil
            }

            // Reconcile before repeating anything. This is the duplicate-submission guard.
            if let applied = try? await reconcile(session: session, wasApplied: wasApplied), applied {
                return HTTPResponse(status: 204)
            }
            _ = transportFailed

            guard attempt < configuration.retry.maxRetries else { throw VerificationError.providerFailure }
            let delay = configuration.retry.backoff(forAttempt: attempt, retryAfter: lastRetryAfter)
            guard session.expiresAt.timeIntervalSince(clock.now) > delay.seconds else {
                throw VerificationError.expired
            }
            try await clock.sleep(for: delay)
            attempt += 1
        }
    }

    private func reconcile(session: VerificationSession,
                           wasApplied: @Sendable (SessionStateBody) -> Bool) async throws -> Bool {
        let state = try await self.state(for: session)
        if let reference = state.reference { self.reference = reference }
        if state.state == .expired { throw VerificationError.expired }
        return wasApplied(state)
    }
}
