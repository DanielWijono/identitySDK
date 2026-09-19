import Foundation
import os
import Testing
import IdentityFlowCore
import IdentityFlowDemoService
@testable import IdentityFlowHTTP

private final class LifecycleTestTransport: HTTPTransport, Sendable {
    private struct State {
        var routes: [String] = []
        var suspendConsentResponse = false
        var consentWasApplied = false
    }

    private let service: DemoVerificationService
    private let state: OSAllocatedUnfairLock<State>

    init(service: DemoVerificationService, suspendConsentResponse: Bool = false) {
        self.service = service
        state = OSAllocatedUnfairLock(initialState: State(suspendConsentResponse: suspendConsentResponse))
    }

    var routes: [String] { state.withLock { $0.routes } }
    var consentWasApplied: Bool { state.withLock { $0.consentWasApplied } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        state.withLock { $0.routes.append("\(request.method) \(request.path)") }
        let suspend = state.withLock {
            guard $0.suspendConsentResponse,
                  request.method == "PUT", request.path.hasSuffix("/consent") else { return false }
            $0.suspendConsentResponse = false
            return true
        }
        let response = await service.handle(request)
        guard suspend else { return response }
        state.withLock { $0.consentWasApplied = true }
        while true {
            try Task.checkCancellation()
            await Task.yield()
        }
    }
}

private func waitUntil(_ condition: @escaping @Sendable () -> Bool) async throws {
    for _ in 0..<100_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for lifecycle test condition")
    throw CancellationError()
}

@Suite struct ForegroundHTTPTransportTests {
    @Test func interruptedMutationReconcilesBeforeItCanRepeat() async throws {
        let service = DemoVerificationService()
        let session = await service.createSession()
        let base = LifecycleTestTransport(service: service, suspendConsentResponse: true)
        let transport = ForegroundHTTPTransport(transport: base, initiallyActive: true)
        let provider = HTTPVerificationProvider(transport: transport)
        let stalePermit = transport.foregroundPermit()

        let consent = Task {
            try await provider.acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        }
        try await waitUntil { base.consentWasApplied }
        transport.leaveForeground()

        #expect(await service.consentWrites == 1)
        #expect(throws: HTTPForegroundError.stalePermit) {
            try transport.enterForeground(stalePermit)
        }
        try transport.enterForeground(transport.foregroundPermit())
        try await consent.value

        #expect(await service.consentWrites == 1, "Reconciliation must replace mutation replay")
        #expect(base.routes.count == 2)
        #expect(base.routes.first?.hasSuffix("/consent") == true)
        #expect(base.routes.last?.contains("GET /sessions/") == true)
    }

    @Test func inactiveTransportSendsNothingUntilFreshActivation() async throws {
        let service = DemoVerificationService()
        let session = await service.createSession()
        let base = LifecycleTestTransport(service: service)
        let transport = ForegroundHTTPTransport(transport: base, initiallyActive: true)
        transport.leaveForeground()

        let consent = Task {
            try await HTTPVerificationProvider(transport: transport)
                .acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        }
        for _ in 0..<100 { await Task.yield() }
        #expect(base.routes.isEmpty)

        try transport.enterForeground(transport.foregroundPermit())
        try await consent.value
        #expect(base.routes.count == 1)
        #expect(await service.consentWrites == 1)
    }

    @Test func callerCancellationDoesNotWaitForForegroundReturn() async throws {
        let service = DemoVerificationService()
        let session = await service.createSession()
        let base = LifecycleTestTransport(service: service)
        let transport = ForegroundHTTPTransport(transport: base, initiallyActive: true)
        transport.leaveForeground()

        let consent = Task {
            try await HTTPVerificationProvider(transport: transport)
                .acknowledgeConsent(Consent(disclosureVersion: "v1"), session: session)
        }
        for _ in 0..<100 { await Task.yield() }
        consent.cancel()
        await #expect(throws: CancellationError.self) { try await consent.value }
        #expect(base.routes.isEmpty)
    }
}
