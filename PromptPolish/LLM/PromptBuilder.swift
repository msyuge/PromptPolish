import Foundation
import NaturalLanguage

struct ChatTurn: Equatable, Sendable {
    enum Role: String, Sendable {
        case system
        case user
    }

    let role: Role
    let content: String
}

/// Собирает сообщения для модели. Промт пользователя оборачивается в теги, чтобы маленькая модель
/// переписывала его, а не отвечала на него.
struct PromptBuilder: Sendable {
    let systemPrompt: String
    /// Короткие подсказки, что лучше работает в конкретном чате (ключ — `ChatTarget.rawValue`).
    let chatStyles: [String: String]

    init(systemPrompt: String, chatStyles: [String: String] = [:]) {
        self.systemPrompt = systemPrompt
        self.chatStyles = chatStyles
    }

    /// Системный промт из `SystemPrompt.txt` и подсказки из `ChatStyles.json` в ресурсах приложения.
    static func bundled(in bundle: Bundle = .main) throws -> PromptBuilder {
        guard let promptURL = bundle.url(forResource: "SystemPrompt", withExtension: "txt"),
              let stylesURL = bundle.url(forResource: "ChatStyles", withExtension: "json") else {
            throw LLMError.missingSystemPrompt
        }
        let text = try String(contentsOf: promptURL, encoding: .utf8)
        let styles = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: stylesURL))
        return PromptBuilder(systemPrompt: text.trimmingCharacters(in: .whitespacesAndNewlines), chatStyles: styles)
    }

    /// `SystemPrompt.txt` копируется в бандл при сборке; его отсутствие — дефект сборки, а не runtime-ошибка.
    static func bundledOrFail() -> PromptBuilder {
        do {
            return try bundled()
        } catch {
            fatalError("SystemPrompt.txt: \(error.localizedDescription)")
        }
    }

    func messages(for userPrompt: String, target: ChatTarget = .generic) -> [ChatTurn] {
        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var header: [String] = []
        if target != .generic, let style = chatStyles[target.rawValue] {
            header.append("Target: \(target.displayName)")
            header.append("Style: \(style)")
        }
        let language = Self.languageName(of: prompt)
        header.append("Language: \(language)")
        // Язык повторяется после промта: маленькая модель лучше всего слушается последней строки.
        let user = header.joined(separator: "\n") + "\n<prompt>\n\(prompt)\n</prompt>\nWrite the result in \(language)."
        return [
            ChatTurn(role: .system, content: systemPrompt),
            ChatTurn(role: .user, content: user),
        ]
    }

    /// Маленькая модель сама плохо держит язык ответа, поэтому язык определяется заранее и называется явно.
    static func languageName(of text: String) -> String {
        let fallback = "the same language as the prompt"
        guard let language = detectLanguage(of: text) else { return fallback }
        return Locale(identifier: "en").localizedString(forLanguageCode: language.rawValue) ?? fallback
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

/// Убирает обёртки, которые маленькие модели добавляют вопреки инструкции.
enum ModelOutputCleaner {
    private static let labelPrefixes = [
        "улучшенный промт:", "улучшенный промпт:", "переписанный промт:", "переписанный промпт:",
        "improved prompt:", "rewritten prompt:", "output:",
    ]

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = strip(text, prefix: "<prompt>", suffix: "</prompt>")
        text = stripCodeFence(text)

        let lowered = text.lowercased()
        if let label = labelPrefixes.first(where: { lowered.hasPrefix($0) }) {
            text = String(text.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for (open, close) in [("\"", "\""), ("«", "»"), ("“", "”")] where text.count > 1 {
            if text.hasPrefix(open), text.hasSuffix(close),
               !text.dropFirst().dropLast().contains(where: { String($0) == open || String($0) == close }) {
                text = String(text.dropFirst().dropLast())
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strip(_ text: String, prefix: String, suffix: String) -> String {
        var text = text
        if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        if text.hasSuffix(suffix) { text = String(text.dropLast(suffix.count)) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripCodeFence(_ text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```"), text.count > 6 else { return text }
        var body = text.dropFirst(3).dropLast(3)
        if let newline = body.firstIndex(of: "\n"), !body[..<newline].contains(" ") {
            body = body[body.index(after: newline)...]
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: LocalizedError {
    case missingSystemPrompt
    case invalidModelID(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingSystemPrompt: "В приложении нет SystemPrompt.txt или ChatStyles.json."
        case let .invalidModelID(id): "Некорректный идентификатор модели: \(id)."
        case .emptyOutput: "Модель вернула пустой ответ."
        }
    }
}
