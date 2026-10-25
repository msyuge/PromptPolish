import AppKit
import KeyboardShortcuts
import os

/// Сценарий целиком: хоткей → текст из поля → определение чата → стриминг в панель → замена.
@MainActor
final class ImproveCoordinator: ObservableObject {
    let permission = AccessibilityPermission()
    let models: ModelStore

    private struct Session {
        let captured: CapturedText
        let preview: PreviewModel
        var generation: Task<Void, Never>?
    }

    private let textBridge: TextBridge
    private let panel = PreviewPanelController()
    private let logger = Logger(subsystem: "local.promptpolish", category: "coordinator")
    private var isCapturing = false
    private var session: Session?

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
        if session != nil {
            panel.bringToFront()
            return
        }
        guard !isCapturing else { return }
        models.prepare()

        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                begin(with: try await textBridge.capture())
            } catch {
                logger.error("capture failed: \(error.localizedDescription, privacy: .public)")
                NSSound.beep()
            }
        }
    }

    private func begin(with captured: CapturedText) {
        let target = ChatTarget.detect(bundleID: captured.app.bundleIdentifier, pageURL: captured.pageURL)
        logger.notice("session started, target=\(target.rawValue, privacy: .public)")

        let preview = PreviewModel(target: target)
        preview.onReplace = { [weak self] in self?.replace() }
        preview.onCopy = { [weak self] in self?.copy() }
        preview.onCancel = { [weak self] in self?.finish() }

        session = Session(captured: captured, preview: preview)
        panel.show(preview, models: models, anchor: captured.anchor)
        session?.generation = Task { [weak self] in
            await self?.generate(captured.text, target: target, into: preview)
        }
    }

    private func generate(_ prompt: String, target: ChatTarget, into preview: PreviewModel) async {
        preview.phase = models.state == .ready ? .generating : .waitingForModel
        var raw = ""
        do {
            for try await chunk in models.engine.improve(prompt, for: target) {
                preview.phase = .generating
                raw += chunk
                preview.text = ModelOutputCleaner.clean(raw)
            }
            preview.phase = preview.text.isEmpty ? .failed(LLMError.emptyOutput.localizedDescription) : .ready
        } catch is CancellationError {
            return
        } catch {
            logger.error("generation failed: \(error.localizedDescription, privacy: .public)")
            preview.phase = .failed(error.localizedDescription)
        }
    }

    private func replace() {
        guard let session, session.preview.canUseResult else { return }
        let text = session.preview.text
        session.preview.phase = .replacing
        // Панель — key-окно: пока она на экране, синтетический ⌘V попал бы в неё, а не в поле ввода.
        panel.close()
        Task {
            do {
                try await textBridge.replace(session.captured, with: text)
                finish()
            } catch {
                logger.error("replace failed: \(error.localizedDescription, privacy: .public)")
                session.preview.phase = .failed("Не удалось заменить текст: \(error.localizedDescription) Скопируйте результат и вставьте вручную.")
                panel.show(session.preview, models: models, anchor: session.captured.anchor)
            }
        }
    }

    /// Пользователь сам просит положить результат в буфер обмена, поэтому здесь буфер меняется намеренно.
    private func copy() {
        guard let session, session.preview.canUseResult else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.preview.text, forType: .string)
        finish()
    }

    private func finish() {
        session?.generation?.cancel()
        session = nil
        panel.close()
    }
}
