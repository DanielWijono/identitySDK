import Foundation
import IdentityFlowCore
import IdentityFlowHTTP

/// In-process implementation of the demo HTTP contract. **Simulation only: it makes no identity
/// decision.** Every outcome is scripted and must be labeled as simulated by any host that shows it.
///
/// It exists to provide contract evidence: it enforces token binding, consent ordering, evidence
/// limits, expiry and idempotency server-side, independently of client code, so a test can assert
/// how many *logical* mutations a run produced rather than how many requests it sent.
public actor DemoVerificationService {
    public enum Decision: Sendable {
        case approve
        case reject
        /// Stays submitted forever, which forces the adapter's pending handoff.
        case hold
        /// Approves only after this many state reads following the commit.
        case approveAfterPolls(Int)
    }

    private struct Record {
        let token: String
        let expiresAt: Date
        var consentVersion: String?
        var evidence: [String: UUID] = [:]
        var digests: [String: String] = [:]
        var submissionKey: UUID?
        var submissionPayload: SubmissionBody?
        var reference: String?
        var cancelled = false
        var pollsSinceSubmission = 0
    }

    private let decision: Decision
    private let clock: any ProviderClock
    private var sessions: [String: Record] = [:]

    /// Counts logical state changes, not requests. The difference is the point of these counters.
    public private(set) var logicalSubmissions = 0
    public private(set) var submissionRequests = 0
    public private(set) var evidenceWrites = 0
    public private(set) var evidenceRequests = 0
    public private(set) var consentWrites = 0

    public init(decision: Decision = .approve, clock: any ProviderClock = SystemProviderClock()) {
        self.decision = decision
        self.clock = clock
    }

    /// Host-side session creation. The SDK never performs this call and holds no service credential.
    public func createSession(lifetime: TimeInterval = 900) -> VerificationSession {
        let id = UUID().uuidString
        let token = "demo-\(UUID().uuidString)"
        let expiresAt = clock.now.addingTimeInterval(lifetime)
        sessions[id] = Record(token: token, expiresAt: expiresAt)
        return VerificationSession(id: id, token: token, expiresAt: expiresAt)
    }

    public func handle(_ request: HTTPRequest) -> HTTPResponse {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "sessions" else { return error(404, "notFound") }
        let id = parts[1]
        guard var record = sessions[id] else { return error(404, "notFound") }
        guard request.headers["Authorization"] == "Bearer \(record.token)" else {
            return error(401, "unauthorized")
        }

        let route = parts.count > 2 ? parts[2] : ""
        let expired = clock.now >= record.expiresAt

        if route == "" && request.method == "GET" {
            if expired { return state(record, forcing: .expired) }
            record.pollsSinceSubmission += record.submissionKey == nil ? 0 : 1
            sessions[id] = record
            return state(record)
        }
        // Every mutation is refused once the session has expired.
        guard !expired else { return error(410, "expired") }

        switch (request.method, route) {
        case ("PUT", "consent"):
            guard let body = try? Wire.decoder.decode(ConsentBody.self, from: request.body ?? Data()) else {
                return error(400, "malformedRequest")
            }
            if let existing = record.consentVersion, existing != body.disclosureVersion {
                return error(409, "consentConflict")
            }
            if record.consentVersion == nil { consentWrites += 1 }
            record.consentVersion = body.disclosureVersion
            sessions[id] = record
            return HTTPResponse(status: 204)

        case ("PUT", "evidence"):
            evidenceRequests += 1
            guard parts.count >= 4, let side = DocumentSide(rawValue: parts[3]) else {
                return error(404, "notFound")
            }
            guard record.consentVersion != nil else { return error(409, "consentRequired") }
            guard request.headers["Content-Type"] == "image/jpeg" else { return error(415, "unsupportedMedia") }
            let bytes = request.body ?? Data()
            guard bytes.count <= 3_000_000 else { return error(413, "evidenceTooLarge") }
            guard let header = request.headers[Wire.headerEvidenceID], let evidenceID = UUID(uuidString: header),
                  let digest = request.headers[Wire.headerEvidenceDigest] else {
                return error(400, "malformedRequest")
            }
            if record.evidence[side.rawValue] == evidenceID {
                // Same logical evidence: a retry, not a second upload.
                guard record.digests[side.rawValue] == digest else { return error(409, "digestConflict") }
                return HTTPResponse(status: 204)
            }
            evidenceWrites += 1
            record.evidence[side.rawValue] = evidenceID
            record.digests[side.rawValue] = digest
            sessions[id] = record
            return HTTPResponse(status: 204)

        case ("POST", "submission"):
            submissionRequests += 1
            guard let keyHeader = request.headers[Wire.headerIdempotencyKey],
                  let key = UUID(uuidString: keyHeader),
                  let body = try? Wire.decoder.decode(SubmissionBody.self, from: request.body ?? Data()) else {
                return error(400, "malformedRequest")
            }
            guard record.evidence[DocumentSide.front.rawValue] != nil,
                  record.evidence[DocumentSide.back.rawValue] != nil else {
                return error(409, "evidenceIncomplete")
            }
            if let existing = record.submissionKey {
                guard existing == key else { return error(409, "submissionConflict") }
                guard record.submissionPayload == body else { return error(409, "submissionConflict") }
                // Replay of the accepted commit. No new logical submission is created.
                return accepted(record)
            }
            logicalSubmissions += 1
            record.submissionKey = key
            record.submissionPayload = body
            record.reference = "demo-ref-\(UUID().uuidString.prefix(8))"
            sessions[id] = record
            return accepted(record)

        case ("POST", "cancel"):
            record.cancelled = true
            sessions[id] = record
            return HTTPResponse(status: 204)

        default:
            return error(404, "notFound")
        }
    }

    // MARK: - Responses

    private func resolvedState(_ record: Record) -> SessionState {
        if record.cancelled { return .cancelled }
        guard record.submissionKey != nil else {
            return record.consentVersion == nil ? .awaitingConsent : .awaitingEvidence
        }
        switch decision {
        case .approve: return .approved
        case .reject: return .rejected
        case .hold: return .submitted
        case .approveAfterPolls(let polls): return record.pollsSinceSubmission >= polls ? .approved : .submitted
        }
    }

    private func state(_ record: Record, forcing forced: SessionState? = nil) -> HTTPResponse {
        let body = SessionStateBody(state: forced ?? resolvedState(record),
                                    expiresAt: record.expiresAt,
                                    reference: record.reference,
                                    receivedEvidence: record.evidence,
                                    submissionKey: record.submissionKey)
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"],
                            body: Wire.encode(body))
    }

    private func accepted(_ record: Record) -> HTTPResponse {
        let body = SubmissionAccepted(reference: record.reference ?? "", state: .submitted)
        return HTTPResponse(status: 202, headers: ["Content-Type": "application/json"],
                            body: Wire.encode(body))
    }

    private func error(_ status: Int, _ code: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"],
                     body: Wire.encode(ErrorBody(code: code)))
    }
}

/// Connects the adapter to the in-process service with no sockets involved.
public struct DemoServiceTransport: HTTPTransport {
    private let service: DemoVerificationService
    public init(service: DemoVerificationService) { self.service = service }
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        await service.handle(request)
    }
}
