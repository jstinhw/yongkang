import Foundation
import Observation
import Sparkle

/// Updates the way VS Code does them: found and downloaded in the background, then one quiet
/// "Restart to Update" instead of a window that interrupts. `SUAutomaticallyUpdate` in Info.plist
/// makes Sparkle download on its own; when the download is ready, Sparkle hands over the block
/// that installs it now, and `ready` holds it until the user asks. Ignored, it installs on quit.
/// Sparkle still shows its own window for a check the user starts, and for an update it cannot
/// install silently — one that needs an administrator's password, say.
///
/// The appcast and the DMG it points at are published by `.github/workflows/release.yml`,
/// signed with the EdDSA key whose public half is in Info.plist.
///
/// It only runs in a Release build with a public key set. A Debug build would otherwise offer to
/// replace itself with the last release, and Sparkle refuses an unsigned feed anyway.
@MainActor @Observable final class Updates: NSObject {
    static let shared = Updates()

    /// The version downloaded and waiting for a restart, which is what the menu item offers.
    private(set) var ready: String?
    @ObservationIgnored private var installNow: (() -> Void)?
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    /// Whether Check for Updates can do anything; the menu item is disabled when not.
    var available: Bool { controller != nil }

    /// Starts the daily check. Called once, at launch.
    func start() {
        guard controller == nil, Online.isRelease, Online.value("SUPublicEDKey") != nil,
            Online.url("SUFeedURL") != nil
        else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    /// Checking again while a check is showing brings its window forward, so the menu item
    /// never needs Sparkle's `canCheckForUpdates` observed.
    func check() { controller?.checkForUpdates(nil) }

    /// Quits, installs the downloaded update and opens the new version.
    func restart() {
        installNow?()
    }
}

extension Updates: @preconcurrency SPUUpdaterDelegate {
    /// Returning true keeps the update waiting for `restart()` rather than starting another
    /// check; it still installs on quit if the user never asks.
    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        ready = item.displayVersionString
        installNow = immediateInstallHandler
        Analytics.capture("update_ready", ["version": item.displayVersionString])
        return true
    }
}
