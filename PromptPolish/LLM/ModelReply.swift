import Foundation

/// Ответ модели: готовый промт или уточняющие вопросы. Разбирается и из неполного текста во время стриминга.
enum ModelReply: Equatable {
    case prompt(String)
    case questions(String)

    /// Блок ``` важнее маркера вопросов: если модель и спросила, и выдала промт, используется промт.
    static func parse(_ raw: String) -> ModelReply {
        let text = withoutReasoning(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let block = fencedBlock(in: text) {
            return .prompt(ModelOutputCleaner.clean(block))
        }
        if let questions = questions(in: text) {
            return .questions(questions)
        }
        return .prompt(ModelOutputCleaner.clean(text))
    }

    /// Рассуждения в `<think>…</think>` не входят в ответ. Незакрытый блок (рассуждение ещё стримится) скрывается целиком.
    static func withoutReasoning(_ raw: String) -> String {
        guard let open = raw.range(of: "<think>") else { return raw }
        guard let close = raw.range(of: "</think>", range: open.upperBound..<raw.endIndex) else {
            return String(raw[..<open.lowerBound])
        }
        return String(raw[..<open.lowerBound]) + withoutReasoning(String(raw[close.upperBound...]))
    }

    /// Вопросы, если в ответе есть маркер. Маленькая модель ставит его не только в начале и иногда повторяет,
    /// поэтому все вхождения маркера (в том числе жирные) вырезаются, а остальной текст сохраняется.
    private static func questions(in text: String) -> String? {
        // Для английской идеи модель переводит маркер вместе с вопросами.
        let markers = [PromptBuilder.questionsMarker, "QUESTIONS:"]
        guard markers.contains(where: { text.range(of: $0, options: .caseInsensitive) != nil }) else { return nil }
        var withoutMarkers = text
        for marker in markers {
            withoutMarkers = withoutMarkers
                .replacingOccurrences(of: "**\(marker)**", with: "\n", options: .caseInsensitive)
                .replacingOccurrences(of: marker, with: "\n", options: .caseInsensitive)
        }
        return withoutMarkers
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Содержимое блока ```: от строки после открывающего ограждения до последнего закрывающего.
    /// Последнего — потому что внутри промта могут быть свои блоки кода. Незакрытый блок (стриминг) берётся до конца.
    static func fencedBlock(in text: String) -> String? {
        guard let open = text.range(of: "```") else { return nil }
        let afterFence = text[open.upperBound...]
        guard let lineEnd = afterFence.firstIndex(of: "\n") else { return "" }
        let contentStart = afterFence.index(after: lineEnd)
        let content = text[contentStart...]
        if let close = content.range(of: "```", options: .backwards) {
            return String(content[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(content).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Убирает обёртки, которые маленькие модели добавляют к промту, и запрещённые заглушки.
enum ModelOutputCleaner {
    private static let labelPrefixes = [
        "улучшенный промт:", "улучшенный промпт:", "итоговый промпт:", "итоговый промт:",
        "improved prompt:", "rewritten prompt:", "final prompt:",
    ]

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        text = strip(text, prefix: "<prompt>", suffix: "</prompt>")

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

    /// Заглушки вида «[укажи аудиторию]» запрещены, но маленькая модель иногда их добавляет.
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
            let isBullet = ["- ", "* ", "• "].contains { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
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
}
