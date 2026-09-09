import Foundation
import Testing
@testable import IdentityFlowCore
import IdentityFlowDemoSupport

private func session(seconds: TimeInterval = 60) -> VerificationSession {
    VerificationSession(id: "synthetic-session", token: "secret-test-token", expiresAt: Date().addingTimeInterval(seconds))
}
private let consent = Consent(disclosureVersion: "sample-v1")

@Test func simulatedOutcomesCleanUpAndRespectOrder() async throws {
    for scenario in [ScriptedProvider.Scenario.approved, .rejected, .pending] {
        let provider = ScriptedProvider(scenario: scenario)
        let source = SyntheticEvidenceSource()
        let outcome = try await VerificationClient(provider: provider).run(session: session(), consent: consent, evidence: source)
        let reference = VerificationReference(sessionID: "synthetic-session", providerReference: "SIMULATED")
        switch scenario {
        case .approved: #expect(outcome == .approved(reference))
        case .rejected: #expect(outcome == .rejected(reference))
        case .pending: #expect(outcome == .pending(reference))
        case .failure: Issue.record("Unexpected scenario")
        }
        #expect(await source.cleanupCount == 1)
        #expect(await provider.events == ["consent", "upload-front", "upload-back", "submit", "decision"])
    }
}

@Test func providerFailureCleansUp() async {
    let source = SyntheticEvidenceSource()
    await #expect(throws: VerificationError.providerFailure) {
        try await VerificationClient(provider: ScriptedProvider(scenario: .failure))
            .run(session: session(), consent: consent, evidence: source)
    }
    #expect(await source.cleanupCount == 1)
}

/// Deliberately ignores task cancellation until explicitly released.
private actor HeldProvider: VerificationProvider {
    var entered = false
    var gate: CheckedContinuation<Void, Never>?
    var uploads = 0
    func acknowledgeConsent(_ consent: Consent, session: VerificationSession) async {
        await withCheckedContinuation { gate = $0; entered = true }
    }
    func release() { gate?.resume(); gate = nil }
    func upload(_ evidence: Evidence, session: VerificationSession) { uploads += 1 }
    func submit(session: VerificationSession, idempotencyKey: UUID) {}
    func decision(session: VerificationSession) -> VerificationOutcome { .cancelled }
    func cancel(session: VerificationSession) {}
}

@Test func cancellationDoesNotWaitForProviderAndLateCompletionCannotUpload() async throws {
    let provider = HeldProvider()
    let client = VerificationClient(provider: provider)
    let source = SyntheticEvidenceSource()
    let task = Task { try await client.run(session: session(), consent: consent, evidence: source) }
    while !(await provider.entered) { await Task.yield() }
    await #expect(throws: VerificationError.sessionAlreadyActive) {
        try await client.run(session: session(), consent: consent, evidence: SyntheticEvidenceSource())
    }
    await client.cancel()
    #expect(try await task.value == .cancelled)
    #expect(await source.cleanupCount == 1)
    await provider.release()
    #expect(await provider.uploads == 0)
}

@Test func hostTaskCancellationConvergesOnCleanup() async throws {
    let provider = HeldProvider()
    let source = SyntheticEvidenceSource()
    let client = VerificationClient(provider: provider)
    let task = Task { try await client.run(session: session(), consent: consent, evidence: source) }
    while !(await provider.entered) { await Task.yield() }
    task.cancel()
    #expect(try await task.value == .cancelled)
    #expect(await source.cleanupCount == 1)
    await provider.release()
}

@Test func expiryTerminatesHeldProvider() async {
    let provider = HeldProvider()
    let source = SyntheticEvidenceSource()
    await #expect(throws: VerificationError.expired) {
        try await VerificationClient(provider: provider).run(session: session(seconds: 0.05), consent: consent, evidence: source)
    }
    #expect(await source.cleanupCount == 1)
    await provider.release()
}

@Test func expiredSessionDoesNotStartProvider() async {
    let provider = ScriptedProvider(scenario: .approved)
    await #expect(throws: VerificationError.expired) {
        try await VerificationClient(provider: provider).run(session: session(seconds: -1), consent: consent, evidence: SyntheticEvidenceSource())
    }
    #expect(await provider.events.isEmpty)
}

@Test func readersAreRevokedAndTokensRedacted() async throws {
    let source = SyntheticEvidenceSource()
    let evidence = try await source.confirmedEvidence(for: .front)
    await source.cleanup()
    await #expect(throws: VerificationError.evidenceFailure) { try await evidence.reader.read() }
    #expect(!String(describing: session()).contains("secret-test-token"))
    #expect(!String(reflecting: session()).contains("secret-test-token"))
}
