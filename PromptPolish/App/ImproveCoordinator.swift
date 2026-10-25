import AppKit
import KeyboardShortcuts
import os

/// Связывает хоткей, чтение текста, генерацию и панель превью.
@MainActor
final class ImproveCoordinator: ObservableObject {
    let permission = AccessibilityPermission()

    private let logger = Logger(subsystem: "local.promptpolish", category: "coordinator")

    func start() {
        KeyboardShortcuts.onKeyUp(for: .improvePrompt) { [weak self] in
            self?.improvePrompt()
        }
        if !permission.isTrusted {
            permission.request()
        }
    }

    func improvePrompt() {
        guard permission.isTrusted else {
            permission.request()
            return
        }
        logger.info("improvePrompt triggered")
        NSSound(named: "Tink")?.play()
    }
}
