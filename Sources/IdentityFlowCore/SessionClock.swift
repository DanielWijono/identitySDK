import Foundation

/// Internal so the public API does not commit to a clock abstraction yet.
protocol SessionClock: Sendable {
    var wallNow: Date { get }
    var elapsed: Duration { get }
    func sleep(until deadline: Duration) async throws
}

struct SystemSessionClock: SessionClock {
    private let clock = ContinuousClock()
    private let origin = ContinuousClock.now
    var wallNow: Date { Date() }
    var elapsed: Duration { origin.duration(to: clock.now) }
    func sleep(until deadline: Duration) async throws {
        try await clock.sleep(until: origin.advanced(by: deadline))
    }
}
