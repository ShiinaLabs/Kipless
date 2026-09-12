import AppKit
import SwiftUI

/// How much of a Session is left, as the ring draws it.
///
/// Pure arithmetic on the Session's absolute deadline, so the answer is right
/// whenever it is asked for — after a long absence, after the Mac slept, or on
/// the very first frame after the popover is reopened.
enum SessionRingProgress {
    /// A full ring at the Session's start, empty at its deadline.
    ///
    /// An idle or indefinite Session reads as full: there is no deadline to
    /// travel towards, and the ring is the countdown's shape rather than a
    /// status light.
    static func progress(session: WakeSession?, at date: Date) -> Double {
        guard let session, let expiresAt = session.expiresAt else { return 1 }

        let total = max(expiresAt.timeIntervalSince(session.startedAt), 1)
        let remaining = max(expiresAt.timeIntervalSince(date), 0)

        return min(max(remaining / total, 0), 1)
    }

    /// Whole seconds left, or `nil` when the Session has no deadline.
    static func remainingSeconds(session: WakeSession?, at date: Date) -> Int? {
        guard let expiresAt = session?.expiresAt else { return nil }

        return max(0, Int(expiresAt.timeIntervalSince(date).rounded(.up)))
    }
}

/// How fast the ring is allowed to travel.
enum SessionRingMotion {
    /// The longest a catch-up may take, however long the popover was closed.
    /// Being away for half an hour must not play back for half an hour.
    static let maximumCatchUpDuration: Double = 0.45

    /// A steady one-second tick moves the ring by a sliver; a catch-up moves it
    /// by however much was missed, but never takes `maximumCatchUpDuration`.
    static func duration(forDelta delta: Double) -> Double {
        switch abs(delta) {
        case ..<0.02: 0.15
        case ..<0.10: 0.25
        case ..<0.30: 0.35
        default: maximumCatchUpDuration
        }
    }

    /// `nil` means "place the ring, do not move it".
    ///
    /// A steady tick is linear so the ring does not visibly ease once a second;
    /// a catch-up eases out because it is a single gesture.
    static func animation(reduceMotion: Bool, delta: Double) -> Animation? {
        guard !reduceMotion else { return nil }

        let duration = duration(forDelta: delta)

        return abs(delta) < 0.02
            ? .linear(duration: duration)
            : .easeOut(duration: duration)
    }
}

/// The countdown's presentation state, kept deliberately apart from the Session
/// it describes.
///
/// `WakeSessionManager` owns when a Session ends. This owns what the popover
/// shows while someone is looking at it — which includes showing nothing at
/// all: the clock only runs when the popover is on screen *and* there is a
/// deadline to count down to, so a Session running in the background produces
/// no UI wake-ups and no redraws.
@MainActor
@Observable
final class SessionPresentationClock {
    /// The time the popover is drawing for. It is never used to decide anything
    /// about the Session — only to place the ring and the countdown text.
    private(set) var now: Date

    /// Whether the popover's window is on screen. The one thing in the popover
    /// that animates by itself asks for this too.
    private(set) var isVisible: Bool

    private let dateProvider: () -> Date
    private let interval: Duration
    private var ticker: Task<Void, Never>?

    init(
        dateProvider: @escaping () -> Date = Date.init,
        interval: Duration = .seconds(1)
    ) {
        self.dateProvider = dateProvider
        self.interval = interval
        // Assume the popover is on screen until the window says otherwise. A
        // wrong `true` costs one second of refreshing; a wrong `false` would
        // freeze the countdown in front of the user.
        self.isVisible = true
        self.now = dateProvider()
    }

    /// Whether the clock is producing UI refreshes. Exposed for tests.
    var isTicking: Bool { ticker != nil }

    /// Tells the clock what it has to draw, and derives from that whether there
    /// is any point in running at all.
    ///
    /// The visibility write is guarded on a real change on purpose. This is
    /// called from the window probe, which reports during a SwiftUI update
    /// pass, and an `@Observable` setter notifies its observers whether or not
    /// the value actually moved — writing unconditionally would invalidate the
    /// view, re-run the probe, and loop forever.
    func update(isVisible: Bool, isCountingDown: Bool) {
        if self.isVisible != isVisible {
            self.isVisible = isVisible
        }

        if isVisible, isCountingDown {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard ticker == nil else { return }

        let interval = self.interval
        now = dateProvider()

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                self.now = self.dateProvider()
            }
        }
    }

    private func stop() {
        ticker?.cancel()
        ticker = nil
    }
}

/// Reports whether the view it is attached to is on screen.
///
/// The popover's window is ordered out when the popover closes rather than torn
/// down, so the content view stays alive and SwiftUI's own lifecycle callbacks
/// do not fire for it. Reading the hosting window is what makes "refresh only
/// while someone is looking" possible at all.
struct WindowVisibilityProbe: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = HostingView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.report()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Hands over the window it lands in, including the move back to `nil`.
    final class HostingView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        var onChange: (Bool) -> Void
        private var observers: [NSObjectProtocol] = []
        private var visibilityObservation: NSKeyValueObservation?
        private weak var window: NSWindow?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
        }

        func attach(to window: NSWindow?) {
            guard window !== self.window else { return }

            detach()
            self.window = window

            guard let window else {
                onChange(false)
                return
            }

            // What is read is always the window's "ordered in" state, which is
            // what changes when the popover is dismissed. Measured against a
            // real window, `isVisible` flips on `orderFront`/`orderOut` at once,
            // while `occlusionState` lags behind — it still reported a window as
            // visible 0.8s after it had been ordered out. The two signals below
            // are therefore only triggers; neither of their own values is used.
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            )

            visibilityObservation = window.observe(\.isVisible) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.report() }
            }

            report()
        }

        func detach() {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []

            visibilityObservation = nil
            window = nil
        }

        func report() {
            onChange(window?.isVisible == true)
        }
    }
}
