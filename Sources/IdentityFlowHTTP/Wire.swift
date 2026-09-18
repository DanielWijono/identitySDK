import Foundation
import IdentityFlowCore

/// Authoritative server state. `reference` is opaque; the SDK never parses meaning from it.
public enum SessionState: String, Sendable, Codable {
    case awaitingConsent, awaitingEvidence, submitted, approved, rejected, cancelled, expired
}

public struct SessionStateBody: Sendable, Codable, Equatable {
    public var state: SessionState
    public var expiresAt: Date
    public var reference: String?
    /// Side raw value to the evidence ID the server currently holds, so a client can tell its own
    /// accepted upload from a superseded one without re-sending bytes.
    public var receivedEvidence: [String: UUID]
    public var submissionKey: UUID?

    public init(state: SessionState, expiresAt: Date, reference: String? = nil,
                receivedEvidence: [String: UUID] = [:], submissionKey: UUID? = nil) {
        self.state = state; self.expiresAt = expiresAt; self.reference = reference
        self.receivedEvidence = receivedEvidence; self.submissionKey = submissionKey
    }
}

public struct ConsentBody: Sendable, Codable, Equatable {
    public var disclosureVersion: String
    public init(disclosureVersion: String) { self.disclosureVersion = disclosureVersion }
}

public struct SubmissionBody: Sendable, Codable, Equatable {
    public var frontEvidenceID: UUID
    public var backEvidenceID: UUID
    public init(frontEvidenceID: UUID, backEvidenceID: UUID) {
        self.frontEvidenceID = frontEvidenceID; self.backEvidenceID = backEvidenceID
    }
}

public struct SubmissionAccepted: Sendable, Codable, Equatable {
    public var reference: String
    public var state: SessionState
    public init(reference: String, state: SessionState) { self.reference = reference; self.state = state }
}

/// Stable machine-readable code plus an optional opaque support reference.
/// Free-form server text is deliberately absent: adapters must not surface it.
public struct ErrorBody: Sendable, Codable, Equatable {
    public var code: String
    public var reference: String?
    public init(code: String, reference: String? = nil) { self.code = code; self.reference = reference }
}

public enum Wire {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encode(_ value: some Encodable) -> Data {
        (try? encoder.encode(value)) ?? Data()
    }

    public static let headerEvidenceID = "X-Evidence-Id"
    public static let headerEvidenceDigest = "X-Evidence-Digest"
    public static let headerIdempotencyKey = "Idempotency-Key"
    public static let headerRetryAfter = "Retry-After"
}

extension VerificationError {
    /// Maps a non-retryable response to a typed error. The server's own text is discarded; only the
    /// stable code participates, and an unrecognized code degrades to a generic provider failure.
    static func from(status: Int, code: String?) -> VerificationError {
        if code == "expired" { return .expired }
        switch status {
        case 401, 403, 404: return .invalidSession
        case 410: return .expired
        default: return .providerFailure
        }
    }
}
