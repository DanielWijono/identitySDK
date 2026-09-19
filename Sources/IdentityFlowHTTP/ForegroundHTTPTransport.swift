import Foundation
import os

/// Capture on foreground entry before scheduling any asynchronous activation work. A later
/// inactivity event invalidates the permit, preventing stale work from reopening network access.
public struct HTTPForegroundPermit: Sendable {
    fileprivate let owner: UUID
    fileprivate let generation: UUID
}

public enum HTTPForegroundError: Error, Sendable, Equatable {
    case stalePermit
}

/// Restricts an HTTP transport to foreground use and cancels its active exchange synchronously.
///
/// Wrap the `URLSessionTransport` supplied to `HTTPVerificationProvider`, retain this wrapper, and
/// forward host lifecycle events to `leaveForeground()` and `enterForeground(_:)`.
///
/// A mutating exchange interrupted by inactivity is ambiguous: the server may have accepted it.
/// After foreground activation, this wrapper reports a connection loss instead of replaying the
/// request. `HTTPVerificationProvider` then reads authoritative state before deciding whether the
/// mutation is safe to repeat. Interrupted GET requests can be repeated directly after activation.
public final class ForegroundHTTPTransport: HTTPTransport, Sendable {
    private let transport: any HTTPTransport
    private let gate: HTTPForegroundGate

    /// The caller must explicitly state whether foreground eligibility has already been
    /// established; this avoids silently enabling network access during application startup.
    public init(transport: any HTTPTransport, initiallyActive: Bool) {
        self.transport = transport
        self.gate = HTTPForegroundGate(initiallyActive: initiallyActive)
    }

    public var isForeground: Bool { gate.isActive }

    public func foregroundPermit() -> HTTPForegroundPermit { gate.permit() }

    public func enterForeground(_ permit: HTTPForegroundPermit) throws {
        try gate.activate(permit)
    }

    /// Closes the gate and cancels active socket work before returning to the lifecycle observer.
    public func leaveForeground() {
        gate.suspend()
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let isRead = request.method.caseInsensitiveCompare("GET") == .orderedSame
        while true {
            try await gate.waitUntilActive()
            try Task.checkCancellation()

            let exchange = Task { try await transport.send(request) }
            guard let token = gate.register(cancel: { exchange.cancel() }) else {
                // Inactivity raced request registration. The child may already have reached the
                // server, so a mutation is ambiguous even though it was cancelled immediately.
                exchange.cancel()
                try await gate.waitUntilActive()
                if isRead { continue }
                throw HTTPTransportError.connectionLost
            }

            let result: Result<HTTPResponse, any Error>
            do {
                result = .success(try await withTaskCancellationHandler {
                    try await exchange.value
                } onCancel: {
                    exchange.cancel()
                })
            } catch {
                result = .failure(error)
            }
            let interrupted = gate.finish(token)
            try Task.checkCancellation()
            guard interrupted else { return try result.get() }
            try await gate.waitUntilActive()
            if isRead { continue }
            throw HTTPTransportError.connectionLost
        }
    }
}

private struct HTTPRequestToken: Sendable {
    let id: UUID
    let generation: UUID
}

/// Lock-backed because lifecycle notification handling must close access synchronously rather than
/// enqueueing an actor hop after the application has already become inactive.
private final class HTTPForegroundGate: Sendable {
    private struct State {
        var active: Bool
        var generation = UUID()
        var inFlight: [UUID: @Sendable () -> Void] = [:]
        var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    }

    private let owner = UUID()
    private let state: OSAllocatedUnfairLock<State>

    init(initiallyActive: Bool) {
        state = OSAllocatedUnfairLock(initialState: State(active: initiallyActive))
    }

    var isActive: Bool { state.withLock { $0.active } }

    func permit() -> HTTPForegroundPermit {
        state.withLock { HTTPForegroundPermit(owner: owner, generation: $0.generation) }
    }

    func activate(_ permit: HTTPForegroundPermit) throws {
        let waiters: [CheckedContinuation<Void, Never>] = try state.withLock {
            guard permit.owner == owner, permit.generation == $0.generation else {
                throw HTTPForegroundError.stalePermit
            }
            $0.active = true
            let pending = Array($0.waiters.values)
            $0.waiters.removeAll()
            return pending
        }
        for waiter in waiters { waiter.resume() }
    }

    func suspend() {
        let cancellations: [@Sendable () -> Void] = state.withLock {
            $0.active = false
            $0.generation = UUID()
            let pending = Array($0.inFlight.values)
            $0.inFlight.removeAll()
            return pending
        }
        for cancel in cancellations { cancel() }
    }

    func register(cancel: @escaping @Sendable () -> Void) -> HTTPRequestToken? {
        state.withLock {
            guard $0.active else { return nil }
            let token = HTTPRequestToken(id: UUID(), generation: $0.generation)
            $0.inFlight[token.id] = cancel
            return token
        }
    }

    /// Returns true when an inactivity event occurred after this exchange was registered.
    func finish(_ token: HTTPRequestToken) -> Bool {
        state.withLock {
            $0.inFlight.removeValue(forKey: token.id)
            return token.generation != $0.generation
        }
    }

    func waitUntilActive() async throws {
        try Task.checkCancellation()
        guard !isActive else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let resumeImmediately = state.withLock {
                    guard !$0.active else { return true }
                    $0.waiters[id] = continuation
                    return false
                }
                if resumeImmediately { continuation.resume() }
            }
            try Task.checkCancellation()
        } onCancel: {
            let continuation = self.state.withLock { $0.waiters.removeValue(forKey: id) }
            continuation?.resume()
        }
    }
}
