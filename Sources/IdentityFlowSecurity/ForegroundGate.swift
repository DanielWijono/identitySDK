import Foundation
import os

/// Capture synchronously when the host becomes active; an inactivity event invalidates it.
public struct VaultForegroundPermit: Sendable {
    fileprivate let owner: UUID
    fileprivate let generation: UUID
}

/// Uses a system lock available at our iOS 16/macOS 13 minimums, without unchecked Sendable.
final class ForegroundGate: Sendable {
    private struct State { var active = false; var generation = UUID() }
    private let owner = UUID()
    private let state = OSAllocatedUnfairLock(initialState: State())
    var isActive: Bool { state.withLock { $0.active } }
    func permit() -> VaultForegroundPermit {
        state.withLock { VaultForegroundPermit(owner: owner, generation: $0.generation) }
    }
    func accepts(_ permit: VaultForegroundPermit) -> Bool {
        state.withLock { permit.owner == owner && permit.generation == $0.generation }
    }
    func activate(_ permit: VaultForegroundPermit) throws {
        try state.withLock {
            guard permit.owner == owner, permit.generation == $0.generation else { throw VaultError.inactive }
            $0.active = true
        }
    }
    func suspend() {
        state.withLock { $0.active = false; $0.generation = UUID() }
    }
}
