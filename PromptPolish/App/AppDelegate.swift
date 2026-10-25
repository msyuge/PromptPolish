import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = ImproveCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit-тесты хостятся в приложении: там не нужны ни хоткей, ни загрузка модели.
        // Переменная окружения XCTest в новых Xcode не выставляется, поэтому проверяется сам фреймворк.
        guard NSClassFromString("XCTestCase") == nil else { return }
        coordinator.start()
    }
}
