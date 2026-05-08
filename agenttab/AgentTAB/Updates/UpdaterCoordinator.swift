import Foundation
import Sparkle

@MainActor
final class UpdaterCoordinator: NSObject {
    let updater: SPUStandardUpdaterController

    override init() {
        // startingUpdater: true → Sparkle starts background scheduler immediately
        updater = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        updater.checkForUpdates(self)
    }
}
