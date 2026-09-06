import Foundation
import Sparkle

@MainActor
final class UpdaterCoordinator: NSObject {
    private let updater: SPUStandardUpdaterController?

    override init() {
        // XCTest launches the app target as its host. Starting Sparkle there
        // can surface configuration/network alerts over the user's desktop,
        // even though no update was requested. Production launches retain the
        // same once-per-day automatic checks.
        updater = Self.shouldStartUpdater()
            ? SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            : nil
        super.init()
    }

    func checkForUpdates() {
        updater?.checkForUpdates(self)
    }

    nonisolated static func shouldStartUpdater(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
            && environment["XCTestBundlePath"] == nil
    }
}
