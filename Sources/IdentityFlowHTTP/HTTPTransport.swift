import Foundation

/// One HTTP exchange. Paths are service-relative, so transports own the base URL.
public struct HTTPRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, path: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method; self.path = path; self.headers = headers; self.body = body
    }
}

/// One HTTP reply.
public struct HTTPResponse: Sendable, Equatable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }

    /// Header lookup is case-insensitive; HTTP field names are not case-sensitive.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A transport failure. Every case is treated as *ambiguous* for mutating requests: the server may
/// already have applied the change. Callers must reconcile rather than blindly repeat a mutation.
public enum HTTPTransportError: Error, Sendable, Equatable {
    case timedOut
    case connectionLost
    case unreachable
    case malformedResponse
}

/// Sends one HTTP exchange. Inject a fake to drive contract tests without sockets.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Default transport. Uses platform trust validation; it never disables certificate checks.
public struct URLSessionTransport: HTTPTransport {
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.path, relativeTo: baseURL) else {
            throw HTTPTransportError.malformedResponse
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw HTTPTransportError.malformedResponse }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String, let value = value as? String { headers[name] = value }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw HTTPTransportError.timedOut
            case .networkConnectionLost, .cannotConnectToHost: throw HTTPTransportError.connectionLost
            case .notConnectedToInternet, .cannotFindHost, .dnsLookupFailed: throw HTTPTransportError.unreachable
            case .cancelled: throw CancellationError()
            default: throw HTTPTransportError.connectionLost
            }
        }
    }
}
