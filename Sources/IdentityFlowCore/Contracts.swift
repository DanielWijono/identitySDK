import Foundation

public enum DocumentSide: String, Sendable, CaseIterable { case front, back }

/// Host-issued credentials. The token stays in memory; descriptions deliberately redact it.
public struct VerificationSession: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: String
    public let token: String
    public let expiresAt: Date
    public init(id: String, token: String, expiresAt: Date) {
        self.id = id; self.token = token; self.expiresAt = expiresAt
    }
    public var description: String { "VerificationSession(<redacted>)" }
    public var debugDescription: String { description }
}

public struct Consent: Sendable {
    public let disclosureVersion: String
    public init(disclosureVersion: String) { self.disclosureVersion = disclosureVersion }
}

public struct VerificationReference: Sendable, Equatable {
    public let sessionID: String
    public let providerReference: String
    public init(sessionID: String, providerReference: String) {
        self.sessionID = sessionID; self.providerReference = providerReference
    }
}

public enum VerificationOutcome: Sendable, Equatable {
    case approved(VerificationReference)
    case rejected(VerificationReference)
    case pending(VerificationReference)
    case cancelled
}

public enum RecoveryAction: Sendable { case retry, retryCleanup, restartSession, contactHostSupport }
public enum VerificationError: Error, Sendable, Equatable {
    case sessionAlreadyActive, expired, invalidSession, providerFailure, evidenceFailure
    case cleanupRequired, cleanupInProgress, noCleanupPending
    public var recoveryAction: RecoveryAction {
        switch self {
        case .expired, .invalidSession: .restartSession
        case .providerFailure: .retry
        case .cleanupRequired, .cleanupInProgress: .retryCleanup
        default: .contactHostSupport
        }
    }
}

public enum VerificationProgress: Sendable, Equatable {
    case consent, capture(DocumentSide), upload(DocumentSide), submit, awaitDecision, finished
}

/// A reader grants bounded access without exposing a persistent file URL.
/// Production implementations must enforce expiry and foreground-only access.
public protocol EvidenceReader: Sendable {
    func read() async throws -> Data
}

public struct Evidence: Sendable {
    public let id: UUID
    public let side: DocumentSide
    public let reader: any EvidenceReader
    public init(id: UUID, side: DocumentSide, reader: any EvidenceReader) {
        self.id = id; self.side = side; self.reader = reader
    }
}

/// Capture/review/storage boundary. Return only confirmed evidence. Cleanup must be idempotent.
/// An implementation must cancel capture and revoke readers on cleanup, including in-flight work.
public protocol EvidenceSource: Sendable {
    func confirmedEvidence(for side: DocumentSide) async throws -> Evidence
    /// Revoke readers before suspending. Throw if deletion fails; subsequent calls must retry it.
    func cleanup() async throws
}

public protocol VerificationProvider: Sendable {
    func acknowledgeConsent(_ consent: Consent, session: VerificationSession) async throws
    func upload(_ evidence: Evidence, session: VerificationSession) async throws
    func submit(session: VerificationSession, idempotencyKey: UUID) async throws
    /// Return pending when the adapter's bounded observation budget elapses.
    func decision(session: VerificationSession) async throws -> VerificationOutcome
    func cancel(session: VerificationSession) async
}
