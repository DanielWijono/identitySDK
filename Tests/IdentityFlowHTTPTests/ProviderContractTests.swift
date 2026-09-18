import Foundation
import os
import Testing
@testable import IdentityFlowHTTP
import IdentityFlowDemoService
import IdentityFlowCore

// MARK: - Doubles

/// Returns from every sleep immediately while advancing virtual time and recording the delay, so
/// backoff and the decision budget are asserted exactly without elapsed wall time.
private final class RecordingClock: ProviderClock, Sendable {
    private struct State {
        // Anchored to real time: VerificationClient runs on its own system clock and would treat
        // an epoch-anchored session as already expired.
        var now = Date()
        var slept: [Duration] = []
        var parked = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())
    /// When set, sleeps suspend until the task is cancelled instead of returning at once. Without
    /// it an instant clock burns the whole decision budget before a test can cancel anything.
    private let parkOnSleep: Bool

    init(parkOnSleep: Bool = false) { self.parkOnSleep = parkOnSleep }

    var now: Date { state.withLock { $0.now } }
    var sleeps: [Duration] { state.withLock { $0.slept } }
    var totalSlept: Double { sleeps.reduce(0) { $0 + $1.seconds } }
    var isParked: Bool { state.withLock { $0.parked } }

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        state.withLock { $0.slept.append(duration); $0.now.addTimeInterval(duration.seconds) }
        guard parkOnSleep else { return }
        state.withLock { $0.parked = true }
        defer { state.withLock { $0.parked = false } }
        while true {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}

private final class FaultTransport: HTTPTransport, Sendable {
    enum Fault: Sendable {
        /// The server applies the request; the client never sees the reply. The ambiguous case.
        case loseResponse(HTTPTransportError)
        /// The request never reaches the server.
        case failBeforeServer(HTTPTransportError)
        case status(Int, retryAfter: String? = nil)
        case malformedBody
    }

    private let service: DemoVerificationService
    private let faults: OSAllocatedUnfairLock<[String: [Fault]]>
    private let seen = OSAllocatedUnfairLock<[String]>(initialState: [])

    init(service: DemoVerificationService, faults: [String: [Fault]] = [:]) {
        self.service = service
        self.faults = OSAllocatedUnfairLock(initialState: faults)
    }

    var routes: [String] { seen.withLock { $0 } }
    func count(_ route: String) -> Int { routes.filter { $0 == route }.count }

    /// Session ids vary per test, so faults are keyed by the route beneath /sessions/{id}.
    private func route(_ request: HTTPRequest) -> String {
        let parts = request.path.split(separator: "/").map(String.init)
        let tail = parts.count > 2 ? parts[2...].joined(separator: "/") : ""
        return "\(request.method) /\(tail)"
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let key = route(request)
        seen.withLock { $0.append(key) }
        let fault: Fault? = faults.withLock { map in
            guard var queue = map[key], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            map[key] = queue
            return next
        }
        switch fault {
        case .failBeforeServer(let error):
            throw error
        case .loseResponse(let error):
            _ = await service.handle(request)
            throw error
        case .status(let status, let retryAfter):
            var headers: [String: String] = [:]
            if let retryAfter { headers[Wire.headerRetryAfter] = retryAfter }
            return HTTPResponse(status: status, headers: headers,
                                body: Wire.encode(ErrorBody(code: "transient")))
        case .malformedBody:
            return HTTPResponse(status: 200, body: Data("{ not json".utf8))
        case nil:
            return await service.handle(request)
        }
    }
}

private struct FixedReader: EvidenceReader {
    let side: DocumentSide
    func read() async throws -> Data { Data("synthetic-jpeg-\(side.rawValue)".utf8) }
}

/// Synthetic evidence with stable ids, so a repeated upload is the *same* logical evidence.
private struct FixedEvidence: EvidenceSource {
    let front = UUID()
    let back = UUID()
    func confirmedEvidence(for side: DocumentSide) async throws -> Evidence {
        Evidence(id: side == .front ? front : back, side: side, reader: FixedReader(side: side))
    }
    func cleanup() async throws {}
}

private func makeProvider(_ clock: RecordingClock, _ transport: FaultTransport,
                          decisionBudget: Duration = .seconds(30)) -> HTTPVerificationProvider {
    // Zero jitter keeps backoff arithmetic exact; the jitter function itself is covered separately.
    let retry = RetryPolicy(jitter: { _ in 1.0 })
    let configuration = HTTPVerificationProvider.Configuration(
        retry: retry, decisionBudget: decisionBudget,
        initialPollInterval: .seconds(1), maxPollInterval: .seconds(5))
    return HTTPVerificationProvider(transport: transport, configuration: configuration, clock: clock)
}

// MARK: - Contract tests

@Suite struct ProviderContractTests {

    @Test func completesWholeContractAndRecordsOneOfEachMutation() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service)
        let client = VerificationClient(provider: makeProvider(clock, transport))

        let outcome = try await client.run(session: session, consent: Consent(disclosureVersion: "v1"),
                                           evidence: FixedEvidence())

        guard case .approved(let reference) = outcome else {
            Issue.record("Expected approval, got \(outcome)"); return
        }
        #expect(reference.sessionID == session.id)
        #expect(!reference.providerReference.isEmpty)
        #expect(await service.consentWrites == 1)
        #expect(await service.evidenceWrites == 2)
        #expect(await service.logicalSubmissions == 1)
    }

    /// The M4 exit gate. The server accepts the commit and the reply is lost. Reconciliation must
    /// recognise the run's own idempotency key and never send a second commit.
    @Test func lostResponseAfterAcceptedCommitProducesExactlyOneSubmission() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service,
                                       faults: ["POST /submission": [.loseResponse(.timedOut)]])
        let client = VerificationClient(provider: makeProvider(clock, transport))

        let outcome = try await client.run(session: session, consent: Consent(disclosureVersion: "v1"),
                                           evidence: FixedEvidence())

        guard case .approved(let reference) = outcome else {
            Issue.record("Expected approval, got \(outcome)"); return
        }
        #expect(!reference.providerReference.isEmpty, "Reference must survive a lost 202")
        #expect(await service.logicalSubmissions == 1)
        // Stronger than counting client calls: the server itself saw only one commit request,
        // because reconciliation replaced the retry.
        #expect(await service.submissionRequests == 1)
        #expect(transport.count("POST /submission") == 1)
    }

    @Test func lostResponseAfterAcceptedUploadDoesNotStoreEvidenceTwice() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service,
                                       faults: ["PUT /evidence/front": [.loseResponse(.connectionLost)]])
        let client = VerificationClient(provider: makeProvider(clock, transport))

        let outcome = try await client.run(session: session, consent: Consent(disclosureVersion: "v1"),
                                           evidence: FixedEvidence())

        guard case .approved = outcome else { Issue.record("Expected approval, got \(outcome)"); return }
        #expect(await service.evidenceWrites == 2, "Front must not be stored twice")
        #expect(await service.evidenceRequests == 2, "Reconciliation must replace the retry")
        #expect(await service.logicalSubmissions == 1)
    }

    /// A repeated commit that does reach the server must be absorbed there too, not just avoided
    /// by the client. This exercises the server-side idempotency key directly.
    @Test func replayedCommitWithSameKeyCreatesNoSecondSubmission() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service)
        let provider = makeProvider(clock, transport)
        let key = UUID()

        try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        let evidence = FixedEvidence()
        for side in DocumentSide.allCases {
            try await provider.upload(try await evidence.confirmedEvidence(for: side), session: session)
        }
        try await provider.submit(session: session, idempotencyKey: key)
        try await provider.submit(session: session, idempotencyKey: key)

        #expect(await service.submissionRequests == 2)
        #expect(await service.logicalSubmissions == 1)
    }

    @Test func conflictingPayloadUnderSameKeyFailsWithoutRetrying() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service)
        let provider = makeProvider(clock, transport)
        let key = UUID()

        try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        let first = FixedEvidence()
        for side in DocumentSide.allCases {
            try await provider.upload(try await first.confirmedEvidence(for: side), session: session)
        }
        try await provider.submit(session: session, idempotencyKey: key)

        // Different evidence ids under the key the server already bound.
        let second = FixedEvidence()
        for side in DocumentSide.allCases {
            try await provider.upload(try await second.confirmedEvidence(for: side), session: session)
        }
        await #expect(throws: VerificationError.providerFailure) {
            try await provider.submit(session: session, idempotencyKey: key)
        }
        #expect(await service.logicalSubmissions == 1)
        #expect(clock.sleeps.isEmpty, "A 409 is a decision, not a transient failure")
    }

    @Test func expiredSessionIsReportedWithoutRetrying() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        // Already past its lifetime on the shared virtual clock.
        let session = await service.createSession(lifetime: -1)
        let transport = FaultTransport(service: service)
        let provider = makeProvider(clock, transport)

        await #expect(throws: VerificationError.expired) {
            try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        }
        #expect(transport.routes.isEmpty, "An expired session must not reach the network")
        #expect(clock.sleeps.isEmpty)
    }

    @Test func rejectedCredentialsAreNotRetried() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let real = await service.createSession()
        let forged = VerificationSession(id: real.id, token: "wrong-token", expiresAt: real.expiresAt)
        let transport = FaultTransport(service: service)
        let provider = makeProvider(clock, transport)

        await #expect(throws: VerificationError.invalidSession) {
            try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: forged)
        }
        #expect(transport.count("PUT /consent") == 1, "401 must not be retried")
        #expect(clock.sleeps.isEmpty)
    }

    @Test func rateLimitHonoursBoundedRetryAfterThenSucceeds() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service,
                                       faults: ["PUT /consent": [.status(429, retryAfter: "2")]])
        let provider = makeProvider(clock, transport)

        try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)

        #expect(clock.sleeps.count == 1)
        #expect(clock.sleeps.first?.seconds == 2.0, "Retry-After must win over exponential backoff")
        #expect(transport.count("PUT /consent") == 2)
        #expect(await service.consentWrites == 1)
    }

    @Test func hostileRetryAfterIsCapped() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service,
                                       faults: ["PUT /consent": [.status(503, retryAfter: "86400")]])
        let provider = makeProvider(clock, transport)

        try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        #expect(clock.sleeps.first?.seconds == 10.0, "Capped at maxRetryAfter, not obeyed literally")
    }

    @Test func persistentServerFailureExhaustsBoundedRetries() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service, faults: [
            "PUT /consent": Array(repeating: .status(503), count: 10)
        ])
        let provider = makeProvider(clock, transport)

        await #expect(throws: VerificationError.providerFailure) {
            try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        }
        // One initial attempt plus the three permitted retries.
        #expect(transport.count("PUT /consent") == 4)
        #expect(clock.sleeps.count == 3)
        #expect(clock.sleeps.map(\.seconds) == [0.5, 1.0, 2.0], "Exponential backoff, capped")
    }

    @Test func malformedStateBodyFailsWithTypedError() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service,
                                       faults: ["GET /": Array(repeating: .malformedBody, count: 5)])
        let provider = makeProvider(clock, transport)

        await #expect(throws: VerificationError.providerFailure) {
            _ = try await provider.decision(session: session)
        }
    }

    @Test func delayedDecisionHandsOffAsPendingAfterTheBudget() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .hold, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service)
        let provider = makeProvider(clock, transport, decisionBudget: .seconds(30))

        try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        let evidence = FixedEvidence()
        for side in DocumentSide.allCases {
            try await provider.upload(try await evidence.confirmedEvidence(for: side), session: session)
        }
        try await provider.submit(session: session, idempotencyKey: UUID())
        let outcome = try await provider.decision(session: session)

        guard case .pending(let reference) = outcome else {
            Issue.record("Expected pending handoff, got \(outcome)"); return
        }
        #expect(!reference.providerReference.isEmpty)
        #expect(clock.totalSlept >= 30.0, "Must observe for the whole budget before handing off")
        #expect(clock.totalSlept < 40.0, "Must not block the UI far beyond the budget")
        // Bounded backoff, not a tight poll loop.
        #expect(clock.sleeps.map(\.seconds).prefix(4) == [1.0, 2.0, 4.0, 5.0])
    }

    @Test func delayedDecisionResolvesWhenTheServerDecides() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approveAfterPolls(3), clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service)
        let client = VerificationClient(provider: makeProvider(clock, transport))

        let outcome = try await client.run(session: session, consent: Consent(disclosureVersion: "v1"),
                                           evidence: FixedEvidence())
        guard case .approved = outcome else { Issue.record("Expected approval, got \(outcome)"); return }
        #expect(clock.totalSlept < 30.0, "Should stop polling as soon as the server decides")
    }

    @Test func userCancellationWhileAwaitingDecisionStopsTheRun() async throws {
        let clock = RecordingClock(parkOnSleep: true)
        let service = DemoVerificationService(decision: .hold, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service)
        let client = VerificationClient(provider: makeProvider(clock, transport))

        let run = Task { try await client.run(session: session, consent: Consent(disclosureVersion: "v1"),
                                              evidence: FixedEvidence()) }
        // The parked clock holds the run inside bounded decision polling, so cancellation is not
        // racing the budget.
        var spins = 0
        while !clock.isParked {
            spins += 1
            try #require(spins < 1_000_000, "Run never reached the decision poll")
            await Task.yield()
        }
        #expect(await service.logicalSubmissions == 1)

        await client.cancel()
        let outcome = try await run.value

        #expect(outcome == .cancelled)
        #expect(await service.logicalSubmissions == 1, "Cancellation must not commit again")
    }

    @Test func evidenceLimitsAreEnforcedByTheServer() async throws {
        let clock = RecordingClock()
        let service = DemoVerificationService(decision: .approve, clock: clock)
        let session = await service.createSession()
        let transport = FaultTransport(service: service)
        let provider = makeProvider(clock, transport)

        try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        let oversized = Evidence(id: UUID(), side: .front, reader: OversizedReader())
        await #expect(throws: VerificationError.providerFailure) {
            try await provider.upload(oversized, session: session)
        }
        #expect(await service.evidenceWrites == 0)
        #expect(clock.sleeps.isEmpty, "413 is not transient")
    }

    @Test func serverSuppliedTextNeverReachesTheCaller() async throws {
        // A hostile server returning a chatty body must not leak it through a typed error.
        let transport = LeakyTransport()
        let clock = RecordingClock()
        let provider = makeProvider(clock, FaultTransport(service: DemoVerificationService(clock: clock)))
        _ = provider
        let direct = HTTPVerificationProvider(transport: transport, clock: clock)
        let session = VerificationSession(id: "s", token: "t",
                                          expiresAt: clock.now.addingTimeInterval(600))
        do {
            try await direct.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
            Issue.record("Expected a typed failure")
        } catch let error as VerificationError {
            #expect(error == .invalidSession)
            #expect(!"\(error)".contains("user@example.com"))
        }
    }
}

private struct OversizedReader: EvidenceReader {
    func read() async throws -> Data { Data(repeating: 0x41, count: 3_000_001) }
}

/// Returns a stable code alongside free-form text the adapter must discard.
private struct LeakyTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = #"{"code":"unauthorized","message":"token for user@example.com is bad","stack":"..."}"#
        return HTTPResponse(status: 401, body: Data(body.utf8))
    }
}
