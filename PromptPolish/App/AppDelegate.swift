import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = ImproveCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit-тесты хостятся в приложении: там не нужны ни хоткей, ни загрузка модели.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        coordinator.start()
    }
}
