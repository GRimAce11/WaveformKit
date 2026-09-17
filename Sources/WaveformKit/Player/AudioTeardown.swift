import Foundation

/// Owns the resources an audio object has to release when it goes away.
///
/// A `@MainActor` class's `deinit` is nonisolated, so under the Swift 6 language mode it cannot
/// touch main-actor-isolated, non-`Sendable` state — which is exactly what stopping an engine,
/// removing a notification observer, or handing back an `AVPlayer` time-observer token involves.
/// Moving those into a plain, non-isolated object solves it: the work happens in *this* type's
/// `deinit`, which only ever touches its own storage.  The owner releases this on the way out,
/// so cleanup still runs at the same moment it always did.
///
/// Anything that can be cancelled from any isolation domain — a `Task`, for instance — does not
/// need this and should simply be cancelled in the owner's own `deinit`.
///
/// ## Ownership
/// Created, mutated, and released on the main actor.  Deliberately not `Sendable`.
final class AudioTeardown {

    /// Notification observer tokens to hand back to `NotificationCenter`.
    ///
    /// Mutable because observers come and go across the owner's lifetime — they are installed on
    /// `play()` and removed on `stop()`, not only at dealloc.
    var observers: [any NSObjectProtocol] = []

    /// Final cleanup: stopping an engine, removing a tap, releasing a time observer.
    ///
    /// - Important: this must **not** capture the owning object. Doing so retains the owner,
    ///   which means it never deallocates, which means this never runs. Capture only the
    ///   specific resources being released.
    var onDeinit: () -> Void = {}

    init() {}

    /// Remove every installed observer. Safe to call repeatedly.
    func removeObservers() {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    deinit {
        removeObservers()
        onDeinit()
    }
}
