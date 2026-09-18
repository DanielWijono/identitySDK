import Foundation

/// Which face of the document is being captured.
///
/// A run always processes ``front`` then ``back``; there is no single-sided mode in this release.
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

/// The user's acknowledgement of a specific disclosure version.
///
/// Construct this only after an explicit user action. Passing it to
/// ``VerificationClient/run(session:consent:evidence:progress:)`` asserts that the user accepted
/// this exact version; local acceptance alone is not a durable audit record, which is why the
/// provider acknowledges it to the backend before any evidence is transferred.
public struct Consent: Sendable {
    /// Identifier of the disclosure text the user accepted, supplied by the host.
    public let disclosureVersion: String
    public init(disclosureVersion: String) { self.disclosureVersion = disclosureVersion }
}

/// Opaque handle for correlating a finished run with the backend.
///
/// Use it to retrieve a decision later, especially after ``VerificationOutcome/pending(_:)``.
/// Neither field carries meaning the SDK interprets.
public struct VerificationReference: Sendable, Equatable {
    /// The host-issued session identifier this run used.
    public let sessionID: String
    /// Provider-assigned reference. Opaque; never parsed by the SDK.
    public let providerReference: String
    public init(sessionID: String, providerReference: String) {
        self.sessionID = sessionID; self.providerReference = providerReference
    }
}

/// How a run finished.
///
/// - Important: None of these cases is an identity decision made by this SDK. The provider or
///   backend decides; a successful upload is not an approval.
public enum VerificationOutcome: Sendable, Equatable {
    /// The provider reported approval.
    case approved(VerificationReference)
    /// The provider reported rejection.
    case rejected(VerificationReference)
    /// No decision arrived within the provider's bounded observation budget.
    ///
    /// This is a legitimate handoff, not a failure: verification may continue on the server after
    /// the UI closes. Retrieve the result later through your own backend using the reference.
    case pending(VerificationReference)
    /// The user cancelled, or the awaiting task was cancelled. Evidence has been cleaned up.
    case cancelled
}

/// What a host should offer the user after a failure.
public enum RecoveryAction: Sendable {
    /// Transient. Starting a fresh run is reasonable.
    case retry
    /// Local evidence still exists. Call ``VerificationClient/retryCleanup()`` on the same client.
    case retryCleanup
    /// The session cannot be reused. Obtain a new one from your backend.
    case restartSession
    /// Not recoverable from inside the SDK.
    case contactHostSupport
}
/// Typed failures. Provider errors are deliberately collapsed into these cases so that arbitrary
/// server text, which may carry personal data, never reaches the host.
public enum VerificationError: Error, Sendable, Equatable {
    /// A run is already in progress on this client. The new request took no ownership of its
    /// evidence source, so the caller still owns it.
    case sessionAlreadyActive
    /// The session passed its backend expiry or the 15-minute local ceiling.
    case expired
    /// Missing or rejected credentials, or an empty identifier.
    case invalidSession
    /// The provider failed. Its original error is intentionally discarded.
    case providerFailure
    /// The evidence source could not supply confirmed evidence for a side.
    case evidenceFailure
    /// Terminal cleanup failed, so local evidence may still exist.
    ///
    /// The client retains the original result and refuses new runs. Keep the same client instance
    /// and call ``VerificationClient/retryCleanup()`` once storage is available again; a successful
    /// retry delivers the original outcome without repeating any upload.
    case cleanupRequired
    /// Another ``VerificationClient/retryCleanup()`` is already running.
    case cleanupInProgress
    /// ``VerificationClient/retryCleanup()`` was called with nothing pending.
    case noCleanupPending

    /// The recovery this error supports.
    public var recoveryAction: RecoveryAction {
        switch self {
        case .expired, .invalidSession: .restartSession
        case .providerFailure: .retry
        case .cleanupRequired, .cleanupInProgress: .retryCleanup
        default: .contactHostSupport
        }
    }
}

/// Coarse progress for driving host UI.
///
/// Delivered through the optional continuation passed to
/// ``VerificationClient/run(session:consent:evidence:progress:)``. Use
/// `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))`: progress is a status indicator,
/// not an event log, so dropping intermediate values is correct.
public enum VerificationProgress: Sendable, Equatable {
    /// Acknowledging consent with the provider.
    case consent
    /// Waiting for the user to confirm one side.
    case capture(DocumentSide)
    /// Transferring one confirmed side.
    case upload(DocumentSide)
    /// Committing the submission.
    case submit
    /// Observing the provider decision within its bounded budget.
    case awaitDecision
    /// Terminal. The stream finishes after this for every accepted run.
    case finished
}

/// A reader grants bounded access without exposing a persistent file URL.
/// Production implementations must enforce expiry and foreground-only access.
public protocol EvidenceReader: Sendable {
    func read() async throws -> Data
}

/// One confirmed, stored document side.
///
/// The bytes are reached only through ``reader``, which the owning ``EvidenceSource`` can revoke.
public struct Evidence: Sendable {
    /// Stable identity for this logical evidence, reused across transport retries so a server can
    /// deduplicate a repeated upload.
    public let id: UUID
    /// Which side this is.
    public let side: DocumentSide
    /// Revocable access to the stored bytes.
    public let reader: any EvidenceReader
    public init(id: UUID, side: DocumentSide, reader: any EvidenceReader) {
        self.id = id; self.side = side; self.reader = reader
    }
}

/// Capture must return only a user-confirmed, normalized JPEG. Do not persist plaintext.
/// Declared here rather than in the storage module so UI capture components can conform
/// without depending on encryption.
public protocol ConfirmedImageCapture: Sendable {
    func confirmedJPEG(for side: DocumentSide) async throws -> Data
    /// Stop owned capture work. The vault adapter independently rejects late results.
    func cancel() async
}

/// Capture/review/storage boundary. Return only confirmed evidence. Cleanup must be idempotent.
/// An implementation must cancel capture and revoke readers on cleanup, including in-flight work.
public protocol EvidenceSource: Sendable {
    func confirmedEvidence(for side: DocumentSide) async throws -> Evidence
    /// Revoke readers before suspending. Throw if deletion fails; subsequent calls must retry it.
    func cleanup() async throws
}

/// The backend boundary. Implement this to connect the workflow to your own service.
///
/// The SDK calls these in order: consent, both uploads, submit, then decision. Implementations must
/// bound their own I/O — an uncooperative provider task may outlive local cancellation, though it
/// can never advance a cancelled run.
///
/// `HTTPVerificationProvider` (IdentityFlowHTTP) implements this over the demo HTTP contract, and
/// `IdentityFlowDemoSupport.ScriptedProvider` provides deterministic outcomes for tests.
public protocol VerificationProvider: Sendable {
    /// Record the accepted disclosure version before any evidence is transferred.
    func acknowledgeConsent(_ consent: Consent, session: VerificationSession) async throws
    /// Transfer one confirmed side. Read bytes through ``Evidence/reader``.
    func upload(_ evidence: Evidence, session: VerificationSession) async throws
    /// Commit the run.
    ///
    /// - Parameters:
    ///   - session: the credentials for this run.
    ///   - idempotencyKey: stable for this logical run across retries. Send it to the server so a
    ///     repeated commit cannot create a second submission.
    func submit(session: VerificationSession, idempotencyKey: UUID) async throws
    /// Observe the decision. Return pending when the adapter's bounded observation budget elapses.
    func decision(session: VerificationSession) async throws -> VerificationOutcome
    /// Best-effort remote cancellation. Never blocks local completion, and failure here must not
    /// mask the terminal result the client already reserved.
    func cancel(session: VerificationSession) async
}
