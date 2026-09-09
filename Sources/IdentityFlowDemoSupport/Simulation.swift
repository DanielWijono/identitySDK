import Foundation
import IdentityFlowCore

/// SIMULATION ONLY. These bytes are not an identity document or a JPEG.
public actor SyntheticEvidenceSource: EvidenceSource {
    private var revoked = false
    public private(set) var cleanupCount = 0
    public init() {}
    public func confirmedEvidence(for side: DocumentSide) throws -> Evidence {
        guard !revoked else { throw VerificationError.evidenceFailure }
        return Evidence(id: UUID(), side: side, reader: Reader(owner: self))
    }
    public func cleanup() { revoked = true; cleanupCount += 1 }
    private func bytes() throws -> Data {
        guard !revoked else { throw VerificationError.evidenceFailure }
        return Data("SIMULATION — SYNTHETIC EVIDENCE — NOT AN IDENTITY DOCUMENT".utf8)
    }
    private struct Reader: EvidenceReader {
        let owner: SyntheticEvidenceSource
        func read() async throws -> Data { try await owner.bytes() }
    }
}

/// An explicit opt-in fake provider. Never use this for identity decisions.
public actor ScriptedProvider: VerificationProvider {
    public enum Scenario: Sendable { case approved, rejected, pending, failure }
    private let scenario: Scenario
    public private(set) var events: [String] = []
    public init(scenario: Scenario) { self.scenario = scenario }
    public func acknowledgeConsent(_ consent: Consent, session: VerificationSession) { events.append("consent") }
    public func upload(_ evidence: Evidence, session: VerificationSession) async throws {
        _ = try await evidence.reader.read()
        events.append("upload-\(evidence.side.rawValue)")
    }
    public func submit(session: VerificationSession, idempotencyKey: UUID) { events.append("submit") }
    public func decision(session: VerificationSession) throws -> VerificationOutcome {
        events.append("decision")
        let reference = VerificationReference(sessionID: session.id, providerReference: "SIMULATED")
        switch scenario {
        case .approved: return .approved(reference)
        case .rejected: return .rejected(reference)
        case .pending: return .pending(reference)
        case .failure: throw VerificationError.providerFailure
        }
    }
    public func cancel(session: VerificationSession) { events.append("cancel") }
}
