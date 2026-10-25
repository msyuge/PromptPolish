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

/// Собирает диалог с моделью: системная инструкция под конкретный чат из `SystemPrompts/SystemPrompt-<чат>.txt`,
/// идея пользователя в тегах `<prompt>` и служебные строки, которые нужны утилите.
struct PromptBuilder: Sendable {
    /// Строка, с которой модель начинает ответ, если задаёт уточняющие вопросы.
    static let questionsMarker = "ВОПРОСЫ:"

    /// Системные инструкции по чатам (ключ — `ChatTarget.rawValue`); `generic` — общая инструкция пользователя.
    let systemPrompts: [String: String]

    init(systemPrompts: [String: String]) {
        self.systemPrompts = systemPrompts
    }

    init(systemPrompt: String) {
        self.init(systemPrompts: [ChatTarget.generic.rawValue: systemPrompt])
    }

    /// Инструкции из ресурсов приложения. Для каждого чата должен быть свой файл.
    static func bundled(in bundle: Bundle = .main) throws -> PromptBuilder {
        var prompts: [String: String] = [:]
        for target in ChatTarget.allCases {
            guard let url = bundle.url(forResource: "SystemPrompt-\(target.rawValue)", withExtension: "txt") else {
                throw LLMError.missingSystemPrompt(target.rawValue)
            }
            prompts[target.rawValue] = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

    func systemPrompt(for target: ChatTarget) -> String {
        systemPrompts[target.rawValue] ?? systemPrompts[ChatTarget.generic.rawValue] ?? ""
    }

    func messages(for idea: String, target: ChatTarget = .generic) -> [ChatTurn] {
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        // Служебные требования относятся к ответу модели, а не к промпту: без явной оговорки
        // модель переносит их в итоговый промпт.
        let language = Self.languageName(of: idea)
        let lines = [
            "Идея пользователя:", "<prompt>", idea, "</prompt>", "",
            "Требования к твоему ответу (не переноси их в сам промпт):",
            "- весь итоговый промпт пиши на языке: \(language);",
            "- не оставляй в промпте заглушек в квадратных скобках;",
            "- если задаёшь уточняющие вопросы, начни ответ со строки «\(Self.questionsMarker)» и задавай их на языке: \(language).",
        ]
        return [
            ChatTurn(role: .system, content: systemPrompt(for: target)),
            ChatTurn(role: .user, content: lines.joined(separator: "\n")),
        ]
    }

    /// Продолжение диалога после ответов пользователя на уточняющие вопросы.
    func followUp(_ history: [ChatTurn], questions: String, answers: String) -> [ChatTurn] {
        let answers = answers.trimmingCharacters(in: .whitespacesAndNewlines)
        return history + [
            ChatTurn(role: .assistant, content: questions),
            ChatTurn(
                role: .user,
                content: "Мои ответы:\n\(answers)\n\nТеперь напиши итоговый промпт. Больше не задавай вопросов."
            ),
        ]
    }

    /// Маленькая модель сама плохо держит язык ответа, поэтому язык определяется заранее и называется явно.
    static func languageName(of text: String) -> String {
        let fallback = "тот же, что у идеи пользователя"
        guard let language = detectLanguage(of: text) else { return fallback }
        return Locale(identifier: "ru").localizedString(forLanguageCode: language.rawValue) ?? fallback
    }

    /// На коротких русских фразах NLLanguageRecognizer часто выбирает украинский, болгарский или казахский.
    /// Неуверенный ответ для кириллицы без украинских букв считается русским.
    private static func detectLanguage(of text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage, dominant != .undetermined else { return nil }

        let cyrillicNeighbours: Set<NLLanguage> = [.ukrainian, .bulgarian, .kazakh, .mongolian, NLLanguage("mk"), NLLanguage("sr"), NLLanguage("be")]
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[dominant] ?? 0
        let hasUkrainianLetters = text.lowercased().contains { "іїєґ".contains($0) }
        if cyrillicNeighbours.contains(dominant), confidence < 0.8, !hasUkrainianLetters {
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
        case let .missingSystemPrompt(target): "В приложении нет системной инструкции SystemPrompt-\(target).txt."
        case let .invalidModelID(id): "Некорректный идентификатор модели: \(id)."
        case .emptyOutput: "Модель вернула пустой ответ."
        }
    }
}
