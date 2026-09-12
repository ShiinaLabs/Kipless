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
        session?.expiresAt.map { remainingSeconds(until: $0, at: date) }
    }

    /// Whole seconds left until `expiresAt`, never negative.
    static func remainingSeconds(until expiresAt: Date, at date: Date) -> Int {
        max(0, Int(expiresAt.timeIntervalSince(date).rounded(.up)))
    }
}

/// How the menu bar writes a countdown down.
///
/// The reading is deliberately coarse: minutes while there is time to spare,
/// seconds only in the last one. A label that rewrote itself every second would
/// wake the app 86,400 times a day to redraw the same pair of characters sixty
/// times over, and a menu bar utility has better uses for the power.
enum MenuBarCountdown {
    /// Shown while a Session runs with no deadline to count down to. It is
    /// static, so it costs nothing.
    static let indefinite = "∞"

    /// The countdown as the menu bar shows it.
    static func text(remainingSeconds: Int) -> String {
        let seconds = max(0, remainingSeconds)

        if seconds >= 3600 {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60

            return minutes == 0
                ? "\(hours)h"
                : "\(hours)h\(String(format: "%02d", minutes))"
        }

        if seconds >= 60 {
            return "\(seconds / 60)m"
        }

        return "0:\(String(format: "%02d", seconds))"
    }

    /// How long until that text changes, or `nil` once it never will.
    ///
    /// The wait is parked on the change itself rather than on a fixed cadence,
    /// so a label reading "29m" costs one wake-up a minute instead of sixty.
    static func nextChangeDelay(remainingSeconds: Int) -> Duration? {
        guard remainingSeconds > 0 else { return nil }

        // A minute display only turns over on a minute boundary; the last
        // minute turns over every second.
        guard remainingSeconds > 60 else { return .seconds(1) }

        return .seconds((remainingSeconds % 60) + 1)
    }

    /// A cadence for `SessionPresentationClock` that refreshes the label only
    /// when the text above is due to change.
    static let cadence: SessionPresentationClock.Cadence = {
        nextChangeDelay(remainingSeconds: $0)
    }
}

/// Whether the menu bar shows the running countdown.
///
/// Off by default. Showing it costs wake-ups the app does not otherwise need,
/// so it stays the user's to turn on.
enum MenuBarCountdownPreference {
    static let storageKey = "menuBarShowsCountdown"
    static let defaultValue = false
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
    /// How long to wait before the next refresh, given how many seconds the
    /// Session has left.
    ///
    /// The popover redraws its ring on a steady beat, so one second is right
    /// there. A menu bar countdown has no reason to be redrawn while its text
    /// is the same string, so it parks its wait on the moment that string
    /// changes instead.
    typealias Cadence = @Sendable (Int) -> Duration?

    /// One refresh a second, for as long as there is a deadline.
    nonisolated static let steady: Cadence = { _ in .seconds(1) }

    /// The time being drawn for. It is never used to decide anything about the
    /// Session — only to place the ring and the countdown text.
    private(set) var now: Date

    /// Whether whatever draws this is on screen.
    private(set) var isVisible: Bool

    /// How long a cadence with nothing left to wait for parks for.
    ///
    /// It never has to elapse: the Session ending replaces the wait through
    /// `update` long before it would.
    private static let waitingForTheSessionToEnd: Duration = .seconds(3600)

    private let dateProvider: () -> Date
    private let cadence: Cadence
    private var expiresAt: Date?
    private var ticker: Task<Void, Never>?

    init(
        cadence: @escaping Cadence = SessionPresentationClock.steady,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.cadence = cadence
        self.dateProvider = dateProvider
        // Assume whatever draws this is on screen until told otherwise. A wrong
        // `true` costs one second of refreshing; a wrong `false` would freeze a
        // countdown in front of the user.
        self.isVisible = true
        self.now = dateProvider()
    }

    /// Whether the clock is producing refreshes. Exposed for tests.
    var isTicking: Bool { ticker != nil }

    /// Tells the clock what it has to draw, and derives from that whether there
    /// is any point in running at all: whatever draws it has to be on screen,
    /// and there has to be a deadline to count down to.
    ///
    /// The stored inputs are only written when they actually change. This is
    /// called from the window probe, which reports during a SwiftUI update
    /// pass, and an `@Observable` setter notifies its observers whether or not
    /// the value moved — writing unconditionally would invalidate the view,
    /// re-run the probe, and loop forever.
    func update(isVisible: Bool, expiresAt: Date?) {
        guard self.isVisible != isVisible || self.expiresAt != expiresAt else { return }

        if self.isVisible != isVisible {
            self.isVisible = isVisible
        }
        if self.expiresAt != expiresAt {
            self.expiresAt = expiresAt
        }

        // A changed input means the wait already parked is timed for the wrong
        // thing, so it is replaced rather than left to finish.
        stop()

        if isVisible, expiresAt != nil {
            start()
        }
    }

    private func start() {
        guard ticker == nil else { return }

        now = dateProvider()

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                let delay = self.nextRefreshDelay()
                try? await Task.sleep(for: delay, tolerance: Self.tolerance(for: delay))
                guard !Task.isCancelled else { return }

                self.now = self.dateProvider()
            }
        }
    }

    /// How long until what is being drawn changes.
    ///
    /// A cadence that has nothing left to wait for — a countdown that has
    /// reached zero has no next change to name — parks until the Session ends
    /// rather than ending the loop itself, so that the only thing that stops
    /// this clock is `update`. A loop that could end on its own would leave a
    /// dead task behind the `ticker` it is still stored in, and the next
    /// deadline would then start a second one.
    private func nextRefreshDelay() -> Duration {
        guard isVisible, let expiresAt else { return Self.waitingForTheSessionToEnd }

        return cadence(SessionRingProgress.remainingSeconds(until: expiresAt, at: now))
            ?? Self.waitingForTheSessionToEnd
    }

    /// A little leeway lets the kernel coalesce this wake-up with others, which
    /// is what Apple's energy guidance asks for. It stays small enough that no
    /// countdown can visibly drift.
    private static func tolerance(for delay: Duration) -> Duration {
        delay >= .seconds(10) ? .seconds(1) : .milliseconds(50)
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
