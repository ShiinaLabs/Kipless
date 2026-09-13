import Foundation
import Sparkle

/// Sparkle, wrapped so the rest of the app does not have to know about it.
///
/// The updater is deliberately quiet until it is asked not to be: Sparkle
/// defaults automatic checks to on, and Kipless's own promise is that it goes
/// online only when the user asks. Checking by hand is always available.
@MainActor
@Observable
final class UpdaterService {
    /// The one updater for the running app. Built at launch rather than on
    /// first use — the Settings window reads its state the moment it opens.
    static let shared = UpdaterService()

    /// The same key `Info.plist` carries, which is where the first-run default
    /// lives. Sparkle reads and writes it through `UserDefaults`.
    private static let automaticChecksKey = "SUEnableAutomaticChecks"

    /// Whether Sparkle may check on its own schedule.
    ///
    /// Held here rather than read back from `UserDefaults` on each access, so
    /// that the toggle in Settings has something to observe.
    private(set) var automaticallyChecksForUpdates = false

    /// `nil` under test — see `isRunningTests`.
    private let controller: SPUStandardUpdaterController?
    /// Sparkle holds its delegates weakly, so this is the reference that keeps
    /// it alive.
    private let updaterDelegate: UpdaterDelegate?

    /// Whether Sparkle is showing something, and therefore whether this is one
    /// of the things holding the app open as a regular app.
    private var isPresentingUpdates = false

    private init() {
        guard !Self.isRunningTests else {
            controller = nil
            updaterDelegate = nil
            return
        }

        let delegate = UpdaterDelegate()
        updaterDelegate = delegate

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = UserDefaults.standard.bool(
            forKey: Self.automaticChecksKey
        )
        controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates

        delegate.onCycleFinished = { [weak self] in
            self?.endPresentingUpdates()
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        UserDefaults.standard.set(enabled, forKey: Self.automaticChecksKey)
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    /// Checks now, whatever the automatic setting says, and reports what it
    /// finds — including that there is nothing to find.
    ///
    /// A check the user asked for is the one case where Sparkle has a window to
    /// show, so the app is held open for as long as the update cycle runs.
    /// Sparkle does ask to be activated itself, but its own source notes that
    /// this is unreliable from an app with no Dock icon.
    func checkForUpdates() {
        beginPresentingUpdates()
        controller?.checkForUpdates(nil)
    }

    private func beginPresentingUpdates() {
        guard !isPresentingUpdates else { return }

        isPresentingUpdates = true
        AppActivation.begin()
    }

    private func endPresentingUpdates() {
        guard isPresentingUpdates else { return }

        isPresentingUpdates = false
        AppActivation.end()
    }

    /// Tests run inside this app, so a Sparkle built here would look for a feed
    /// and, with automatic checks on, reach the network from a test run.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

/// The one thing Kipless needs to hear from Sparkle: that it is done showing
/// whatever it was showing.
@MainActor
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var onCycleFinished: (() -> Void)?

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        onCycleFinished?()
    }
}
