import Foundation
@testable import Kipless

/// Records what `WakeSessionManager` asked of the assertion layer, without
/// touching real power management.
///
/// It records an ordered event log rather than plain counters so tests can check
/// the thing that actually matters: that an assertion is handed back *before*
/// the next one is created, and that two are never held at once.
@MainActor
final class MockSleepAssertionManager: SleepAsserting {
    enum Event: Equatable {
        case acquire(WakeMode)
        case release
    }

    private(set) var events: [Event] = []

    /// How many assertions the last call would have left held.
    private(set) var heldCount = 0

    /// The most assertions ever held at the same time. Must never exceed 1.
    private(set) var maxHeldCount = 0

    /// Set to make the next `acquire` fail.
    var errorToThrow: Error?

    var acquiredModes: [WakeMode] {
        events.compactMap { event in
            guard case let .acquire(mode) = event else { return nil }
            return mode
        }
    }

    var releaseCount: Int {
        events.filter { $0 == .release }.count
    }

    var isHolding: Bool { heldCount > 0 }

    func acquire(for mode: WakeMode) throws {
        events.append(.acquire(mode))
        if let errorToThrow {
            throw errorToThrow
        }
        heldCount += 1
        maxHeldCount = max(maxHeldCount, heldCount)
    }

    func release() {
        events.append(.release)
        heldCount = 0
    }
}
