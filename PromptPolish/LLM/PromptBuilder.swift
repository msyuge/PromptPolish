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

    /// Код языка промта (например, "ru") для постобработки ответа.
    static func languageCode(of text: String) -> String? {
        detectLanguage(of: text)?.rawValue
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

    /// Названия разделов, которые модель берёт из английских подсказок, в русском промте заменяются на русские.
    private static let russianSections: [(String, String)] = [
        ("Answer format", "Формат ответа"), ("Requirements", "Требования"), ("Constraints", "Ограничения"),
        ("Context", "Контекст"), ("Question", "Вопрос"), ("Task", "Задача"), ("Role", "Роль"),
    ]
    private static let sectionNames = Set(russianSections.flatMap { [$0.0, $0.1] })

    static func clean(_ raw: String, languageCode: String? = nil) -> String {
        normalizeStructure(cleanWrapping(raw), russian: languageCode == "ru")
    }

    /// Выравнивает структуру: `Раздел: текст`, пункты `- текст`, без пустых строк (кроме блоков кода).
    static func normalizeStructure(_ text: String, russian: Bool) -> String {
        var inCode = false
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCode.toggle()
                lines.append(line)
                continue
            }
            if inCode {
                lines.append(line)
                continue
            }
            if trimmed.isEmpty { continue }
            lines.append(normalizeLine(trimmed, russian: russian))
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizeLine(_ line: String, russian: Bool) -> String {
        if let marker = line.first, "-•*".contains(marker), line.count > 1,
           !line.hasPrefix("**"), !line.hasPrefix("--") {
            return "- " + line.dropFirst().trimmingCharacters(in: .whitespaces)
        }
        guard let colon = line.firstIndex(of: ":") else { return line }
        var name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        guard sectionNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return line }
        if russian, let pair = russianSections.first(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame }) {
            name = pair.1
        }
        let rest = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? "\(name):" : "\(name): \(rest)"
    }

    private static func cleanWrapping(_ raw: String) -> String {
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
        return removePlaceholders(from: text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Заглушки вида «[укажи аудиторию]» запрещены промтом, но маленькая модель иногда их добавляет.
    /// Совпадает только текст в скобках, начинающийся со строчной буквы, не прилегающий к идентификатору
    /// и без `:`/`=`/кавычек — так не задеваются `array[index]`, `[String: Int]`, `[1, 2]`. Код в ``` не трогается.
    private static let placeholder = try! NSRegularExpression(
        pattern: #"(?<![\w\])])\s?\[(?=[a-zа-яё])[^\[\]\n`:="]{2,80}\]"#
    )

    static func removePlaceholders(from text: String) -> String {
        var inCode = false
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                lines.append(line)
                continue
            }
            guard !inCode else {
                lines.append(line)
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            guard placeholder.firstMatch(in: line, range: range) != nil else {
                lines.append(line)
                continue
            }
            let isBullet = line.trimmingCharacters(in: .whitespaces).hasPrefix("- ")
            var cleaned = placeholder.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            cleaned = cleaned.replacingOccurrences(of: #"\s+([.,;:!?])"#, with: "$1", options: .regularExpression)
            let meaningful = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-•*:;,. ").union(.whitespaces))
            // Пункт списка, который держался на заглушке, бессмысленен без неё.
            if isBullet || meaningful.isEmpty { continue }
            lines.append(cleaned)
        }
        return lines.joined(separator: "\n")
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
