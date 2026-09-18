import Foundation

/// Injected so tests run the real backoff arithmetic without elapsed time.
public protocol ProviderClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

/// Real time and real sleeping.
public struct SystemProviderClock: ProviderClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

/// Bounds automatic retries.
///
/// Only transient outcomes are retried: 429, 500, 502, 503, 504 and transport failures. Auth
/// failures, conflicts and expired sessions are decisions the server already made, so repeating
/// them cannot change the result.
public struct RetryPolicy: Sendable {
    /// Automatic retries after the first attempt.
    public var maxRetries: Int
    public var baseBackoff: Duration
    public var maxBackoff: Duration
    /// A hostile or broken `Retry-After` must not park the run until the session dies.
    public var maxRetryAfter: Duration
    /// Full jitter. Tests substitute a deterministic function.
    public var jitter: @Sendable (Double) -> Double

    public init(maxRetries: Int = 3,
                baseBackoff: Duration = .milliseconds(500),
                maxBackoff: Duration = .seconds(5),
                maxRetryAfter: Duration = .seconds(10),
                jitter: @escaping @Sendable (Double) -> Double = { Double.random(in: 0...$0) }) {
        self.maxRetries = maxRetries
        self.baseBackoff = baseBackoff
        self.maxBackoff = maxBackoff
        self.maxRetryAfter = maxRetryAfter
        self.jitter = jitter
    }

    /// Transient by contract. Everything else — including 409 conflicts and auth failures — is a
    /// decision the server already made, so repeating it cannot change the outcome.
    public static func isRetryable(status: Int) -> Bool {
        status == 429 || status == 500 || status == 502 || status == 503 || status == 504
    }

    public func backoff(forAttempt attempt: Int, retryAfter: String?) -> Duration {
        if let retryAfter, let seconds = Self.parseRetryAfter(retryAfter) {
            return min(seconds, maxRetryAfter)
        }
        let exponential = baseBackoff * Int(pow(2.0, Double(max(0, attempt))))
        let capped = min(exponential, maxBackoff)
        return capped.scaled(by: jitter(1.0))
    }

    /// Delta-seconds form only. An HTTP-date form is ignored rather than guessed at, which falls
    /// back to exponential backoff instead of trusting a value we cannot interpret.
    static func parseRetryAfter(_ value: String) -> Duration? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let seconds = Double(trimmed), seconds >= 0, seconds.isFinite else { return nil }
        return .seconds(seconds)
    }
}

extension Duration {
    func scaled(by factor: Double) -> Duration {
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return .seconds(max(0, seconds * factor))
    }

    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
