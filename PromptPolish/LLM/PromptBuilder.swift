import Foundation
import NaturalLanguage

struct ChatTurn: Equatable, Sendable {
    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

/// Язык комплекта системных инструкций. Маленькая модель держит язык промпта, только когда инструкции
/// на том же языке, поэтому для идеи на кириллице берётся русский комплект, для остальных — английский.
enum PromptLanguage: String, CaseIterable, Sendable {
    case ru
    case en

    static func of(_ idea: String) -> PromptLanguage {
        var cyrillic = 0
        var latin = 0
        for scalar in idea.unicodeScalars where CharacterSet.letters.contains(scalar) {
            if (0x0400...0x04FF).contains(scalar.value) { cyrillic += 1 } else if scalar.isASCII { latin += 1 }
        }
        // Русские идеи часто содержат английские термины («объясни closures в Swift»), поэтому
        // хватает 30% кириллицы; в английской идее кириллица случайно почти не встречается.
        return cyrillic > 0 && cyrillic * 10 >= (cyrillic + latin) * 3 ? .ru : .en
    }

    var title: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        }
    }

    /// Строка, с которой модель начинает ответ, если задаёт уточняющие вопросы.
    var questionsMarker: String {
        switch self {
        case .ru: "ВОПРОСЫ:"
        case .en: "QUESTIONS:"
        }
    }
}

/// Собирает диалог с моделью: системная инструкция под чат и язык идеи из
/// `SystemPrompts/SystemPrompt-<чат>-<язык>.txt`, идея в тегах `<idea>` и служебные строки на том же языке.
struct PromptBuilder: Sendable {
    /// Маркеры уточняющих вопросов всех комплектов: модель иногда переводит маркер.
    static let questionsMarkers = PromptLanguage.allCases.map(\.questionsMarker)

    /// Системные инструкции (ключ — `"<чат>-<язык>"`, например `claude-ru`).
    let systemPrompts: [String: String]

    init(systemPrompts: [String: String]) {
        self.systemPrompts = systemPrompts
    }

    /// Одна инструкция для всех чатов и языков (для тестов).
    init(systemPrompt: String) {
        self.init(systemPrompts: Dictionary(uniqueKeysWithValues: PromptLanguage.allCases.map {
            (Self.key(.generic, $0), systemPrompt)
        }))
    }

    static func key(_ target: ChatTarget, _ language: PromptLanguage) -> String {
        "\(target.rawValue)-\(language.rawValue)"
    }

    /// Инструкции из ресурсов приложения. Для каждого чата и языка должен быть свой файл.
    static func bundled(in bundle: Bundle = .main) throws -> PromptBuilder {
        var prompts: [String: String] = [:]
        for target in ChatTarget.allCases {
            for language in PromptLanguage.allCases {
                let name = "SystemPrompt-\(key(target, language))"
                guard let url = bundle.url(forResource: name, withExtension: "txt") else {
                    throw LLMError.missingSystemPrompt(name)
                }
                prompts[key(target, language)] = try String(contentsOf: url, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return PromptBuilder(systemPrompts: prompts)
    }

    /// Инструкции копируются в бандл при сборке; их отсутствие — дефект сборки, а не runtime-ошибка.
    static func bundledOrFail() -> PromptBuilder {
        do {
            return try bundled()
        } catch {
            fatalError(error.localizedDescription)
        }
    }

    func systemPrompt(for target: ChatTarget, language: PromptLanguage) -> String {
        systemPrompts[Self.key(target, language)] ?? systemPrompts[Self.key(.generic, language)] ?? ""
    }

    func messages(for idea: String, target: ChatTarget = .generic) -> [ChatTurn] {
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = PromptLanguage.of(idea)
        // Служебные требования явно отделены от промпта: без оговорки модель переносит их в результат.
        // Язык назван последней строкой — маленькая модель лучше всего слушается конца запроса.
        let lines: [String]
        switch language {
        case .ru:
            lines = [
                "Идея пользователя:", "<idea>", idea, "</idea>", "",
                "Требования к ответу (не переноси их в сам промпт):",
                "- пользователь вставит промпт в чат как есть: промпт должен просить ассистента сразу выполнить задачу из идеи, а не написать, улучшить или сгенерировать промпт;",
                "- никаких заглушек в квадратных скобках;",
                "- если задаёшь уточняющие вопросы, начни ответ со строки «\(language.questionsMarker)».",
            ] + (IdeaClarity.needsClarification(idea) ? [
                "- идея требует уточнения: она короткая или ссылается на то, чего ты не знаешь (например, «мой проект»). Задай уточняющие вопросы о том, без чего промпт пришлось бы угадывать.",
            ] : []) + [
                "",
                "Весь промпт (или вопросы) пиши на языке: \(Self.languageName(of: idea, in: .ru)).",
            ]
        case .en:
            lines = [
                "User idea:", "<idea>", idea, "</idea>", "",
                "Requirements for your reply (do not copy them into the prompt):",
                "- the user will paste the prompt into the chat as is: it must ask the assistant to do the task from the idea right away, never to write, improve or generate a prompt;",
                "- no placeholders in square brackets;",
                "- if you ask clarifying questions, start your reply with the line \"\(language.questionsMarker)\".",
            ] + (IdeaClarity.needsClarification(idea) ? [
                "- the idea needs clarification: it is short or refers to something you don't know (for example, \"my project\"). Ask clarifying questions about what you would otherwise have to guess.",
            ] : []) + [
                "",
                "Write the entire prompt (or the questions) in \(Self.languageName(of: idea, in: .en)).",
            ] + [Self.languageDirective(for: idea)].compactMap { $0 }
        }
        return [
            ChatTurn(role: .system, content: systemPrompt(for: target, language: language)),
            ChatTurn(role: .user, content: lines.joined(separator: "\n")),
        ]
    }

    /// Продолжение диалога после ответов пользователя на уточняющие вопросы.
    func followUp(_ history: [ChatTurn], questions: String, answers: String) -> [ChatTurn] {
        let answers = answers.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = switch PromptLanguage.of(idea(in: history)) {
        case .ru: "Мои ответы:\n\(answers)\n\nТеперь напиши итоговый промпт в блоке кода, на том же языке. Больше не задавай вопросов."
        case .en: "My answers:\n\(answers)\n\nNow write the final prompt in a code block, in the same language as before. Do not ask more questions."
        }
        return history + [
            ChatTurn(role: .assistant, content: questions),
            ChatTurn(role: .user, content: content),
        ]
    }

    /// Пользователь нажал «Уточнить»: промпт не попал в задачу, модель должна задать вопросы, а не гадать снова.
    func requestingQuestions(_ history: [ChatTurn], reply: String) -> [ChatTurn] {
        let language = PromptLanguage.of(idea(in: history))
        let content = switch language {
        case .ru: "Этот промпт не попал в мою задачу. Задай 2–3 уточняющих вопроса о том, чего тебе не хватает, — начни ответ со строки «\(language.questionsMarker)». Промпт пока не пиши."
        case .en: "This prompt missed what I need. Ask 2–3 clarifying questions about what is missing; start your reply with the line \"\(language.questionsMarker)\". Do not write the prompt yet."
        }
        return history + [
            ChatTurn(role: .assistant, content: reply),
            ChatTurn(role: .user, content: content),
        ]
    }

    /// Повторный запрос с перечнем найденных дефектов промпта, на языке комплекта инструкций.
    func correcting(_ history: [ChatTurn], reply: String, issues: [PromptIssue]) -> [ChatTurn] {
        let idea = idea(in: history)
        let language = PromptLanguage.of(idea)
        let languageName = Self.languageName(of: idea, in: language)
        let ru = language == .ru
        var problems: [String] = []
        for issue in issues {
            switch issue {
            case .metaTask:
                problems.append(ru
                    ? "- промпт просит написать промпт, а должен просить ассистента сразу выполнить мою задачу;"
                    : "- the prompt asks the assistant to write a prompt; it must ask the assistant to do my task right away;")
            case let .templateEcho(fragments):
                let examples = fragments.prefix(3).map { ru ? "«\($0)»" : "\"\($0)\"" }.joined(separator: ", ")
                problems.append(ru
                    ? "- в промпт переписаны правила, описания разделов или пример из твоей инструкции (\(examples)) — убери их и напиши конкретное содержание моей задачи;"
                    : "- the prompt copies your instructions, section descriptions or example (\(examples)); remove them and write the specific content of my task;")
            case .degenerate:
                problems.append(ru
                    ? "- ответ пустой или зациклился (строка повторяется) — напиши промпт заново, кратко и без повторов;"
                    : "- the reply is empty or stuck in a loop (a line repeats); write the prompt again, concise and without repetition;")
            case .wrongLanguage:
                let directive = Self.languageDirective(for: idea).map { " " + $0 } ?? ""
                problems.append(ru
                    ? "- промпт написан не на языке: \(languageName) — перепиши весь промпт на языке: \(languageName);"
                    : "- the prompt is not in \(languageName); rewrite the whole prompt in \(languageName).\(directive)")
            case let .brokenTags(tags):
                let names = tags.map { "<\($0)>" }.joined(separator: ", ")
                problems.append(ru
                    ? "- теги \(names) не закрыты или закрыты без открытия — оберни каждый раздел в пару тегов, например <role>…</role>;"
                    : "- the tags \(names) are not closed or are closed without being opened; wrap every section in a pair of tags, for example <role>…</role>;")
            }
        }
        let header = ru ? "Исправь промпт:" : "Fix the prompt:"
        let footer = ru
            ? "Сохрани структуру и язык. Ответь промптом в блоке кода, без вопросов."
            : "Keep the structure and the language. Reply with the prompt in a code block, without questions."
        return history + [
            ChatTurn(role: .assistant, content: reply),
            ChatTurn(role: .user, content: ([header] + problems + [footer]).joined(separator: "\n")),
        ]
    }

    /// Идея из первого запроса диалога (между тегами <idea>).
    private func idea(in history: [ChatTurn]) -> String {
        guard let request = history.first(where: { $0.role == .user })?.content,
              let start = request.range(of: "<idea>\n"), let end = request.range(of: "\n</idea>") else { return "" }
        return String(request[start.upperBound..<end.lowerBound])
    }

    /// Маленькая модель сама плохо держит язык ответа, поэтому язык определяется заранее и называется явно —
    /// на языке комплекта инструкций.
    static func languageName(of text: String, in language: PromptLanguage = .en) -> String {
        let fallback = language == .ru ? "тот же, что у идеи" : "the language of the idea"
        guard let detected = detectLanguage(of: text) else { return fallback }
        return Locale(identifier: language.rawValue).localizedString(forLanguageCode: detected.rawValue) ?? fallback
    }

    /// Требование писать на языке идеи, сформулированное на этом же языке, — для английского комплекта
    /// и идей на других языках латиницей.
    static func languageDirective(for idea: String) -> String? {
        switch languageCode(of: idea) {
        case "ru": "Весь промпт пиши на русском языке."
        case "uk": "Весь промпт пиши українською мовою."
        case "de": "Schreibe den gesamten Prompt auf Deutsch."
        case "fr": "Rédige tout le prompt en français."
        case "es": "Escribe todo el prompt en español."
        default: nil
        }
    }

    /// Код языка текста ("ru", "en"…), чтобы проверить, что промпт написан на языке идеи.
    static func languageCode(of text: String) -> String? {
        detectLanguage(of: text)?.rawValue
    }

    /// На коротких русских фразах NLLanguageRecognizer уверенно выбирает украинский, болгарский или казахский
    /// («сравни тарифы мобильных операторов» — казахский). Кириллица без букв, которых нет в русском,
    /// считается русской независимо от уверенности.
    private static func detectLanguage(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else { return nil }

        let cyrillicNeighbours: Set<NLLanguage> = [.ukrainian, .bulgarian, .kazakh, .mongolian, NLLanguage("mk"), NLLanguage("sr"), NLLanguage("be"), NLLanguage("ky"), NLLanguage("tg")]
        let nonRussianLetters = "іїєґўәғқңөұүһјљњћђџ"
        let hasNonRussianLetters = text.lowercased().contains { nonRussianLetters.contains($0) }
        if cyrillicNeighbours.contains(dominant), !hasNonRussianLetters {
            return .russian
        }
        return dominant
    }
}

enum LLMError: LocalizedError {
    case missingSystemPrompt(String)
    case invalidModelID(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case let .missingSystemPrompt(name): "В приложении нет системной инструкции \(name).txt."
        case let .invalidModelID(id): "Некорректный идентификатор модели: \(id)."
        case .emptyOutput: "Модель не смогла составить промт. Попробуйте ещё раз или выберите в меню модель побольше."
        }
    }
}
