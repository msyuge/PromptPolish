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
        /// Сколько раз модель уже просили исправить дефекты промпта.
        var corrections: Int
        /// Последний готовый ответ модели — нужен, чтобы по кнопке «Уточнить» попросить у неё вопросы.
        var lastReply: String?
        var generation: Task<Void, Never>?
    }

    private let textBridge: TextBridge
    private let panel = PreviewPanelController()
    private let logger = Logger(subsystem: "com.alekseimaksimov.promptpolish", category: "coordinator")
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
        // Модель грузится по первому ⌥⌘P, а не при запуске: на Mac с 8 ГБ иначе начинается своп.
        if models.loadsAtLaunch {
            models.prepare()
        }
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
        preview.onClarify = { [weak self] in self?.askForQuestions() }

        models.beginUse()
        let builder = prompts.builder
        let idea = IdeaNormalizer.stripPromptRequest(captured.text)
        session = Session(
            captured: captured,
            preview: preview,
            builder: builder,
            turns: builder.messages(for: idea, target: target),
            idea: idea,
            corrections: 0,
            lastReply: nil
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
                // Петлю обрываем сразу, а не досчитываем до лимита токенов.
                if PromptQuality.isLooping(raw) {
                    logger.notice("generation is looping, stopped early")
                    break
                }
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
                if !issues.isEmpty, session.corrections < PromptQuality.maxCorrections {
                    logger.notice("prompt issues \(String(describing: issues), privacy: .public), asking model to rewrite")
                    self.session?.corrections += 1
                    // Пустой или зацикленный ответ модели не показываем: он закрепляет петлю. Запрос повторяется
                    // с того же места, а случайность генерации даёт другой результат.
                    self.session?.turns = issues.contains(.degenerate)
                        ? turns
                        : session.builder.correcting(turns, reply: raw, issues: issues)
                    preview.apply(.prompt(""))
                    startGeneration()
                    return
                }
                // Если дефекты остались и после исправлений, строки с ними вырезаются.
                if !issues.isEmpty {
                    logger.notice("prompt issues remain after corrections \(String(describing: issues), privacy: .public)")
                }
                let final = issues.isEmpty
                    ? prompt
                    : PromptQuality.removingDefects(from: prompt, systemPrompt: systemPrompt, idea: session.idea)
                self.session?.lastReply = raw
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

    /// Промпт не попал в задачу: модель задаёт уточняющие вопросы, после ответов пишет промпт заново.
    private func askForQuestions() {
        guard var session, session.preview.canClarify, let reply = session.lastReply else { return }
        logger.notice("user asked for clarifying questions")
        session.turns = session.builder.requestingQuestions(session.turns, reply: reply)
        session.corrections = 0
        session.lastReply = nil
        session.preview.apply(.prompt(""))
        self.session = session
        startGeneration()
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
        guard let session else { return }
        session.generation?.cancel()
        self.session = nil
        panel.close()
        models.endUse()
    }
}
