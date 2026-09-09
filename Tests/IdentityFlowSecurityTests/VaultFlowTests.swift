import Foundation
import Testing
import os
@testable import IdentityFlowCore
@testable import IdentityFlowSecurity

private actor TestGate {
    private var arrived = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func hold() async {
        if released { return }
        await withCheckedContinuation {
            waiter = $0; arrived = true
            observers.forEach { $0.resume() }; observers.removeAll()
        }
    }
    func wait() async {
        if arrived { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { released = true; waiter?.resume(); waiter = nil }
}

private struct SyntheticCapture: ConfirmedImageCapture {
    var gate: TestGate? = nil
    func confirmedJPEG(for side: DocumentSide) async -> Data {
        if let gate { await gate.hold() }
        return Data("SYNTHETIC \(side.rawValue)".utf8)
    }
    func cancel() async {}
}

private enum Decision: CaseIterable, Sendable { case approved, rejected, pending, failure }
private actor Provider: VerificationProvider {
    let decisionValue: Decision
    let gate: TestGate?
    let beforeDecision: @Sendable () -> Void
    var uploads: [Evidence] = []
    var submissions = 0
    init(_ decision: Decision = .approved, gate: TestGate? = nil,
         beforeDecision: @escaping @Sendable () -> Void = {}) {
        decisionValue = decision; self.gate = gate; self.beforeDecision = beforeDecision
    }
    func acknowledgeConsent(_ consent: Consent, session: VerificationSession) {}
    func upload(_ evidence: Evidence, session: VerificationSession) async throws {
        #expect(!(try await evidence.reader.read()).isEmpty)
        uploads.append(evidence)
    }
    func submit(session: VerificationSession, idempotencyKey: UUID) { submissions += 1 }
    func decision(session: VerificationSession) async throws -> VerificationOutcome {
        if let gate { await gate.hold() }
        beforeDecision()
        let ref = VerificationReference(sessionID: session.id, providerReference: "synthetic")
        switch decisionValue {
        case .approved: return .approved(ref)
        case .rejected: return .rejected(ref)
        case .pending: return .pending(ref)
        case .failure: throw VerificationError.providerFailure
        }
    }
    func cancel(session: VerificationSession) {}
}

private let consent = Consent(disclosureVersion: "synthetic-v1")
private func session() -> VerificationSession {
    .init(id: "synthetic", token: "synthetic", expiresAt: Date().addingTimeInterval(60))
}

@available(macOS 15, iOS 18, *)
private struct Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("flow-" + UUID().uuidString)
    let keys = MemoryKeys()
    let vault: EvidenceVault
    init() { vault = EvidenceVault(root: root, keys: keys) }
    func source(_ session: VerificationSession, gate: TestGate? = nil) -> VaultEvidenceSource {
        VaultEvidenceSource(sessionID: session.id, expiresAt: session.expiresAt,
                            capture: SyntheticCapture(gate: gate), vault: vault)
    }
    func assertEmpty() throws {
        #expect(keys.state.withLock { $0.keys.isEmpty })
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}

@available(macOS 15, iOS 18, *)
@Test(arguments: Decision.allCases)
private func terminalFlowPurgesVault(decision: Decision) async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let provider = Provider(decision)
    let client = VerificationClient(provider: provider)
    let session = session()
    if decision == .failure {
        await #expect(throws: VerificationError.providerFailure) {
            try await client.run(session: session, consent: consent, evidence: fixture.source(session))
        }
    } else {
        let result = try await client.run(session: session, consent: consent, evidence: fixture.source(session))
        let ref = VerificationReference(sessionID: session.id, providerReference: "synthetic")
        switch decision {
        case .approved: #expect(result == .approved(ref))
        case .rejected: #expect(result == .rejected(ref))
        case .pending: #expect(result == .pending(ref))
        case .failure: Issue.record("Unexpected failure")
        }
    }
    try fixture.assertEmpty()
    for evidence in await provider.uploads {
        await #expect(throws: VaultError.revoked) { try await evidence.reader.read() }
    }
}

@available(macOS 15, iOS 18, *)
@Test(arguments: [false, true])
private func cancellationPurgesEncryptedEvidence(hostCancellation: Bool) async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let gate = TestGate()
    let provider = Provider(gate: gate)
    let client = VerificationClient(provider: provider)
    let session = session()
    let task = Task { try await client.run(session: session, consent: consent, evidence: fixture.source(session)) }
    await gate.wait()
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).count == 2)
    if hostCancellation { task.cancel() } else { await client.cancel() }
    #expect(try await task.value == .cancelled)
    try fixture.assertEmpty()
    await gate.release()
}

@available(macOS 15, iOS 18, *)
@Test(arguments: Decision.allCases)
private func cleanupFailurePreservesResultAndRetriesOnlyDeletion(decision: Decision) async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let keys = fixture.keys
    let provider = Provider(decision, beforeDecision: { keys.state.withLock { $0.locked = true } })
    let client = VerificationClient(provider: provider)
    let session = session()
    await #expect(throws: VerificationError.cleanupRequired) {
        try await client.run(session: session, consent: consent, evidence: fixture.source(session))
    }
    #expect(await client.requiresCleanup)
    await #expect(throws: VerificationError.cleanupRequired) {
        try await client.run(session: session, consent: consent, evidence: fixture.source(session))
    }
    for evidence in await provider.uploads {
        await #expect(throws: VaultError.revoked) { try await evidence.reader.read() }
    }
    await #expect(throws: VerificationError.cleanupRequired) { try await client.retryCleanup() }
    keys.state.withLock { $0.locked = false }
    if decision == .failure {
        await #expect(throws: VerificationError.providerFailure) { try await client.retryCleanup() }
    } else {
        let result = try await client.retryCleanup()
        let ref = VerificationReference(sessionID: session.id, providerReference: "synthetic")
        switch decision {
        case .approved: #expect(result == .approved(ref))
        case .rejected: #expect(result == .rejected(ref))
        case .pending: #expect(result == .pending(ref))
        case .failure: break
        }
    }
    #expect(!(await client.requiresCleanup))
    #expect(await provider.submissions == 1)
    #expect(await provider.uploads.count == 2)
    try fixture.assertEmpty()
    await #expect(throws: VerificationError.noCleanupPending) { try await client.retryCleanup() }
}

private struct ExpiryClock: SessionClock {
    let gate: TestGate
    let wallNow = Date()
    var elapsed: Duration { .zero }
    func sleep(until deadline: Duration) async throws { await gate.hold() }
}

@available(macOS 15, iOS 18, *)
@Test private func coreExpiryTimerCleansVaultWhileProviderIsHeld() async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let providerGate = TestGate(), timerGate = TestGate()
    let client = VerificationClient(provider: Provider(gate: providerGate), clock: ExpiryClock(gate: timerGate))
    let session = session()
    let task = Task { try await client.run(session: session, consent: consent, evidence: fixture.source(session)) }
    await providerGate.wait()
    await timerGate.wait()
    await timerGate.release()
    await #expect(throws: VerificationError.expired) { try await task.value }
    try fixture.assertEmpty()
    await providerGate.release()
}

@available(macOS 15, iOS 18, *)
@Test private func lateCaptureCannotWriteAfterCleanup() async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let gate = TestGate()
    let source = fixture.source(session(), gate: gate)
    let captureTask = Task { try await source.confirmedEvidence(for: .front) }
    await gate.wait()
    try await source.cleanup()
    try fixture.assertEmpty()
    await gate.release()
    await #expect(throws: VaultError.revoked) { try await captureTask.value }
    try fixture.assertEmpty()
}

@available(macOS 15, iOS 18, *)
@Test private func staleActivationCannotReopenInactiveVault() async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let stale = fixture.vault.foregroundPermit()
    fixture.vault.leaveForeground()
    await #expect(throws: VaultError.inactive) { try await fixture.vault.enterForeground(stale) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let source = fixture.source(session())
    let evidence = try await source.confirmedEvidence(for: .front)
    fixture.vault.leaveForeground()
    await #expect(throws: VaultError.inactive) { try await evidence.reader.read() }
    try await source.cleanup()
    try fixture.assertEmpty()
}

@available(macOS 15, iOS 18, *)
@Test private func fileDeletionFailureRetainsCleanupUntilRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let fail = OSAllocatedUnfairLock(initialState: true)
    let keys = MemoryKeys()
    let vault = EvidenceVault(root: root, keys: keys, removeFile: { url in
        if fail.withLock({ $0 }) { throw VaultError.fileFailure }
        try FileManager.default.removeItem(at: url)
    })
    try await vault.enterForeground(vault.foregroundPermit())
    let session = session()
    let client = VerificationClient(provider: Provider())
    let source = VaultEvidenceSource(sessionID: session.id, expiresAt: session.expiresAt,
                                     capture: SyntheticCapture(), vault: vault)
    await #expect(throws: VerificationError.cleanupRequired) {
        try await client.run(session: session, consent: consent, evidence: source)
    }
    #expect(keys.state.withLock { $0.keys.isEmpty }) // Key deletion precedes failed file deletion.
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 2)
    fail.withLock { $0 = false }
    _ = try await client.retryCleanup()
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}

@available(macOS 15, iOS 18, *)
@Test private func cleanupDuringSessionCreationDoesNotLeakKeys() async throws {
    // Both actor jobs start together. Awaiting both results ensures there is no abandoned begin.
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let source = fixture.source(session())
    let task = Task { try await source.confirmedEvidence(for: .front) }
    try await source.cleanup()
    _ = await task.result
    try fixture.assertEmpty()
}

@available(macOS 15, iOS 18, *)
@Test(arguments: [false, true])
private func interruptedCleanupPreservesCancelledOrExpiredResult(expired: Bool) async throws {
    let fixture = Fixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try await fixture.vault.enterForeground(fixture.vault.foregroundPermit())
    let providerGate = TestGate(), timerGate = TestGate()
    let client = VerificationClient(provider: Provider(gate: providerGate), clock: ExpiryClock(gate: timerGate))
    let session = session()
    let task = Task { try await client.run(session: session, consent: consent, evidence: fixture.source(session)) }
    await providerGate.wait()
    await timerGate.wait()
    fixture.keys.state.withLock { $0.locked = true }
    if expired { await timerGate.release() } else { await client.cancel() }
    await #expect(throws: VerificationError.cleanupRequired) { try await task.value }
    fixture.keys.state.withLock { $0.locked = false }
    if expired {
        await #expect(throws: VerificationError.expired) { try await client.retryCleanup() }
    } else {
        #expect(try await client.retryCleanup() == .cancelled)
    }
    try fixture.assertEmpty()
    await providerGate.release()
    await timerGate.release()
}

private actor RetrySource: EvidenceSource {
    let gate = TestGate()
    var attempts = 0
    func confirmedEvidence(for side: DocumentSide) throws -> Evidence { throw VerificationError.evidenceFailure }
    func cleanup() async throws {
        attempts += 1
        if attempts == 1 { throw VaultError.fileFailure }
        await gate.hold()
    }
}

@Test private func concurrentCleanupRetriesAreSerialized() async throws {
    let source = RetrySource()
    let client = VerificationClient(provider: Provider())
    await #expect(throws: VerificationError.cleanupRequired) {
        try await client.run(session: session(), consent: consent, evidence: source)
    }
    let retry = Task { try await client.retryCleanup() }
    await source.gate.wait()
    await #expect(throws: VerificationError.cleanupInProgress) { try await client.retryCleanup() }
    await source.gate.release()
    await #expect(throws: VerificationError.evidenceFailure) { try await retry.value }
    #expect(await source.attempts == 2)
    #expect(!(await client.requiresCleanup))
}
