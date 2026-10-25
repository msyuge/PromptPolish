import AppKit

/// Связывает хоткей, чтение текста, генерацию и панель превью.
@MainActor
final class ImproveCoordinator: ObservableObject {
    func start() {}

    func improvePrompt() {
        NSSound.beep()
    }
}
