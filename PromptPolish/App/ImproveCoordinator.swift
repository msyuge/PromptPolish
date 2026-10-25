import AppKit
import KeyboardShortcuts
import os

/// Сценарий целиком: хоткей → текст из поля → определение чата → стриминг в панель → замена.
@MainActor
final class ImproveCoordinator: ObservableObject {
    let permission = AccessibilityPermission()
    let models: ModelStore
    let prompts: SystemPromptStore

    private struct Session {
        let captured: CapturedText
        let preview: PreviewModel
        /// Инструкции на момент начала сессии: правки в редакторе не меняют уже идущий диалог.
        let builder: PromptBuilder
        /// Диалог с моделью: растёт, когда пользователь отвечает на уточняющие вопросы.
        var turns: [ChatTurn]
        /// Идея без обращения к утилите («сделай промпт для…»).
        let idea: String
        /// Дефекты промпта исправляются автоматически не больше одного раза.
        var corrected: Bool
        var generation: Task<Void, Never>?
    }

    private let textBridge: TextBridge
    private let panel = PreviewPanelController()
    private let logger = Logger(subsystem: "local.promptpolish", category: "coordinator")
    private var isCapturing = false
    private var session: Session?

    init(textBridge: TextBridge = SystemTextBridge(), prompts: SystemPromptStore = .bundled(), models: ModelStore = ModelStore()) {
        self.textBridge = textBridge
        self.prompts = prompts
        self.models = models
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
        preview.onAnswer = { [weak self] in self?.answerQuestions() }

        let builder = prompts.builder
        let idea = IdeaNormalizer.stripPromptRequest(captured.text)
        session = Session(
            captured: captured,
            preview: preview,
            builder: builder,
            turns: builder.messages(for: idea, target: target),
            idea: idea,
            corrected: false
        )
        panel.show(preview, models: models, anchor: captured.anchor)
        startGeneration()
    }

    private func startGeneration() {
        guard let session else { return }
        let turns = session.turns
        let preview = session.preview
        self.session?.generation = Task { [weak self] in
            await self?.generate(turns, into: preview)
        }
    }

    private func generate(_ turns: [ChatTurn], into preview: PreviewModel) async {
        preview.phase = models.state == .ready ? .generating : .waitingForModel
        var raw = ""
        do {
            for try await chunk in models.engine.respond(to: turns) {
                preview.phase = .generating
                raw += chunk
                preview.apply(ModelReply.parse(raw))
            }
            switch ModelReply.parse(raw) {
            case .questions:
                logger.notice("model asked clarifying questions")
                session?.turns.append(ChatTurn(role: .assistant, content: raw))
                preview.phase = .needsAnswers
            case let .prompt(prompt):
                guard let session else { return }
                let systemPrompt = turns.first?.content ?? ""
                let issues = PromptQuality.issues(in: prompt, idea: session.idea, systemPrompt: systemPrompt)
                if !issues.isEmpty, !session.corrected {
                    logger.notice("prompt issues \(String(describing: issues), privacy: .public), asking model to rewrite")
                    self.session?.corrected = true
                    self.session?.turns = session.builder.correcting(turns, reply: raw, issues: issues)
                    preview.apply(.prompt(""))
                    startGeneration()
                    return
                }
                // Если модель повторила копирование и после исправления, скопированные строки вырезаются.
                let final = issues.contains { if case .templateEcho = $0 { true } else { false } }
                    ? PromptQuality.removingEcho(from: prompt, systemPrompt: systemPrompt)
                    : prompt
                preview.apply(.prompt(final))
                preview.phase = final.isEmpty ? .failed(LLMError.emptyOutput.localizedDescription) : .ready
            }
        } catch is CancellationError {
            return
        } catch {
            logger.error("generation failed: \(error.localizedDescription, privacy: .public)")
            preview.phase = .failed(error.localizedDescription)
        }
    }

    private func answerQuestions() {
        guard var session, session.preview.canSendAnswer,
              let questions = session.turns.last, questions.role == .assistant else { return }
        session.turns = session.builder.followUp(Array(session.turns.dropLast()), questions: questions.content, answers: session.preview.answer)
        session.preview.answer = ""
        session.preview.apply(.prompt(""))
        self.session = session
        startGeneration()
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
