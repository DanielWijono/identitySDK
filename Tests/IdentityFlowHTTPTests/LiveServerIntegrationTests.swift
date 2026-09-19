#if os(macOS)
import Foundation
import Darwin
import Testing
import IdentityFlowCore
@testable import IdentityFlowHTTP

private enum LiveServerError: Error {
    case startupFailed(String)
    case invalidStartupMessage
    case unexpectedStatus(Int)
}

/// Owns a child process running the independent Python server on an ephemeral loopback port.
private final class LiveServer {
    let baseURL: URL

    private let process: Process
    private let output: Pipe

    private init(baseURL: URL, process: Process, output: Pipe) {
        self.baseURL = baseURL
        self.process = process
        self.output = output
    }

    static func start(loseSubmissionResponse: Bool = false) throws -> LiveServer {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = repository.appendingPathComponent("Examples/DemoHTTPServer/server.py")
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "--port", "0"]
            + (loseSubmissionResponse ? ["--lose-submission-response-once"] : [])
        process.standardOutput = output
        process.standardError = output
        try process.run()

        let line = try readLine(from: output.fileHandleForReading)
        guard process.isRunning else {
            throw LiveServerError.startupFailed(String(decoding: line, as: UTF8.self))
        }
        struct Startup: Decodable { let baseURL: URL }
        guard let startup = try? JSONDecoder().decode(Startup.self, from: line) else {
            process.terminate()
            process.waitUntilExit()
            throw LiveServerError.invalidStartupMessage
        }
        return LiveServer(baseURL: startup.baseURL, process: process, output: output)
    }

    func stop() {
        guard process.isRunning else { return }
        // The URLSession connection pool may keep HTTP/1.1 handlers alive beyond the test. This
        // process is test-owned and has no persistent state, so stop it deterministically.
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }

    private static func readLine(from handle: FileHandle) throws -> Data {
        var line = Data()
        while let byte = try handle.read(upToCount: 1), !byte.isEmpty {
            if byte[byte.startIndex] == 0x0A { return line }
            line.append(byte)
        }
        return line
    }
}

private struct CreatedSession: Decodable {
    let id: String
    let token: String
    let expiresAt: Date
}

private struct ServerStats: Decodable {
    let consentWrites: Int
    let evidenceRequests: Int
    let evidenceWrites: Int
    let submissionRequests: Int
    let logicalSubmissions: Int
    let lostSubmissionResponses: Int
}

private func createSession(at baseURL: URL, scenario: String = "approve") async throws -> VerificationSession {
    var request = URLRequest(url: baseURL.appendingPathComponent("sessions"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "scenario": scenario,
        "lifetimeSeconds": 120,
    ])
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = try #require((response as? HTTPURLResponse)?.statusCode)
    guard status == 201 else { throw LiveServerError.unexpectedStatus(status) }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let created = try decoder.decode(CreatedSession.self, from: data)
    return VerificationSession(id: created.id, token: created.token, expiresAt: created.expiresAt)
}

private func serverStats(at baseURL: URL) async throws -> ServerStats {
    let url = baseURL.appendingPathComponent("__test__/stats")
    let (data, response) = try await URLSession.shared.data(from: url)
    let status = try #require((response as? HTTPURLResponse)?.statusCode)
    guard status == 200 else { throw LiveServerError.unexpectedStatus(status) }
    return try JSONDecoder().decode(ServerStats.self, from: data)
}

private struct LiveReader: EvidenceReader {
    let side: DocumentSide
    func read() async throws -> Data { Data("synthetic-jpeg-\(side.rawValue)".utf8) }
}

private struct LiveEvidence: EvidenceSource {
    private let front = UUID()
    private let back = UUID()

    func confirmedEvidence(for side: DocumentSide) async throws -> Evidence {
        Evidence(id: side == .front ? front : back, side: side, reader: LiveReader(side: side))
    }

    func cleanup() async throws {}
}

private func liveProvider(baseURL: URL) -> HTTPVerificationProvider {
    let retry = RetryPolicy(baseBackoff: .milliseconds(10), maxBackoff: .milliseconds(50))
    let configuration = HTTPVerificationProvider.Configuration(
        retry: retry,
        decisionBudget: .seconds(2),
        initialPollInterval: .milliseconds(10),
        maxPollInterval: .milliseconds(50)
    )
    return HTTPVerificationProvider(
        transport: URLSessionTransport(baseURL: baseURL),
        configuration: configuration
    )
}

@Suite(.serialized)
struct LiveServerIntegrationTests {
    @Test func URLSessionCompletesIndependentWireContract() async throws {
        let server = try LiveServer.start()
        defer { server.stop() }
        let session = try await createSession(at: server.baseURL)
        let client = VerificationClient(provider: liveProvider(baseURL: server.baseURL))

        let outcome = try await client.run(
            session: session,
            consent: Consent(disclosureVersion: "v1"),
            evidence: LiveEvidence()
        )

        guard case .approved(let reference) = outcome else {
            Issue.record("Expected approval, got \(outcome)")
            return
        }
        #expect(reference.sessionID == session.id)
        #expect(!reference.providerReference.isEmpty)
        let stats = try await serverStats(at: server.baseURL)
        #expect(stats.consentWrites == 1)
        #expect(stats.evidenceRequests == 2)
        #expect(stats.evidenceWrites == 2)
        #expect(stats.submissionRequests == 1)
        #expect(stats.logicalSubmissions == 1)
    }

    @Test func URLSessionReconcilesCommitAfterRealConnectionLoss() async throws {
        let server = try LiveServer.start(loseSubmissionResponse: true)
        defer { server.stop() }
        let session = try await createSession(at: server.baseURL)
        let client = VerificationClient(provider: liveProvider(baseURL: server.baseURL))

        let outcome = try await client.run(
            session: session,
            consent: Consent(disclosureVersion: "v1"),
            evidence: LiveEvidence()
        )

        guard case .approved(let reference) = outcome else {
            Issue.record("Expected approval after reconciliation, got \(outcome)")
            return
        }
        #expect(!reference.providerReference.isEmpty)
        let stats = try await serverStats(at: server.baseURL)
        #expect(stats.lostSubmissionResponses == 1)
        #expect(stats.logicalSubmissions == 1, "A lost response must not create a second submission")
    }
}
#endif
