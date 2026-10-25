import AppKit
import KeyboardShortcuts
import os

/// Связывает хоткей, чтение текста, генерацию и панель превью.
@MainActor
final class ImproveCoordinator: ObservableObject {
    let permission = AccessibilityPermission()
    let models: ModelStore

    private let textBridge: TextBridge
    private let logger = Logger(subsystem: "local.promptpolish", category: "coordinator")
    private var currentTask: Task<Void, Never>?

    init(textBridge: TextBridge = SystemTextBridge(), engine: LLMEngine? = nil) {
        self.textBridge = textBridge
        self.models = ModelStore(engine: engine ?? LLMEngine(builder: .bundledOrFail()))
    }

    func start() {
        KeyboardShortcuts.onKeyUp(for: .improvePrompt) { [weak self] in
            self?.improvePrompt()
        }
        if !permission.isTrusted {
            permission.request()
        }
        models.prepare()
    }

    func improvePrompt() {
        guard permission.isTrusted else {
            permission.request()
            return
        }
        guard currentTask == nil else { return }
        currentTask = Task { [weak self] in
            await self?.runBridgeCheck()
            self?.currentTask = nil
        }
    }

    /// Этап 3: проверка TextBridge без модели — текст заменяется на себя же с меткой.
    private func runBridgeCheck() async {
        do {
            let captured = try await textBridge.capture()
            try await textBridge.replace(captured, with: "[PromptPolish] " + captured.text)
        } catch {
            logger.error("bridge failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }
}
