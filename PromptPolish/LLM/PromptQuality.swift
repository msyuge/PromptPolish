import Foundation

/// Убирает из идеи обращение к самой утилите: «сделай промпт для …» — это просьба к PromptPolish,
/// а не часть задачи. Без этого модель пишет мета-промпт «Напиши промпт, чтобы…».
enum IdeaNormalizer {
    private static let promptRequest = try! NSRegularExpression(
        pattern: #"^\s*(пожалуйста,?\s*)?(сделай|напиши|составь|создай|сгенерируй|подготовь|придумай|улучши|перепиши|write|create|make|generate)\s+(мне\s+|me\s+)?(a\s+)?((хороший|подробный|детальный|качественный|правильный|идеальный|good|detailed)\s+)?(промпт|промт|prompt)\s*(для|чтобы|на|о|об|про|по|к|for|to|that)?\s*((ассистента|ии|ai|модели|нейросети|бота|чата|chatgpt|claude|gemini|deepseek|perplexity|grok|copilot|assistant|model)\s*,?\s*)?((чтобы|который|которая|that|to)\s+)?((он|она|оно|it)\s+)?((мог|могла|смог|смогла|could|can)\s+)?[\s:,.—-]*"#,
        options: [.caseInsensitive]
    )

    /// Промпт для генератора картинок, видео или музыки — сама задача, а не обращение к утилите.
    private static let generators = try! NSRegularExpression(
        pattern: #"midjourney|stable\s*diffusion|dall|sora|flux|kandinsky|кандинск|шедеврум|suno|runway|leonardo|ideogram|veo|kling|картин|изображен|видео|музык|image|video|music"#,
        options: [.caseInsensitive]
    )

    static func stripPromptRequest(_ idea: String) -> String {
        let range = NSRange(idea.startIndex..., in: idea)
        guard generators.firstMatch(in: idea, range: range) == nil,
              let match = promptRequest.firstMatch(in: idea, range: range),
              let matched = Range(match.range, in: idea) else { return idea }
        let rest = idea[matched.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard rest.count >= 3 else { return idea }
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }
}

/// Дефекты готового промпта, которые исправляются одним повторным запросом к модели.
enum PromptIssue: Equatable {
    /// Промпт просит чат написать промпт вместо того, чтобы поставить ему задачу.
    case metaTask
    /// В промпт переписаны фразы из системной инструкции (описания разделов и правила).
    case templateEcho([String])
}

enum PromptQuality {
    static func issues(in prompt: String, idea: String, systemPrompt: String) -> [PromptIssue] {
        var issues: [PromptIssue] = []
        if MetaPromptDetector.isMetaPrompt(prompt, idea: idea) {
            issues.append(.metaTask)
        }
        let echoed = echoedFragments(in: prompt, systemPrompt: systemPrompt)
        if !echoed.isEmpty {
            issues.append(.templateEcho(echoed))
        }
        return issues
    }

    /// Фразы системной инструкции (не короче 4 слов), которые дословно встречаются в промпте.
    /// Совпадение такой длины не бывает случайным: модель переписала описание вместо содержания.
    static func echoedFragments(in prompt: String, systemPrompt: String) -> [String] {
        let normalizedPrompt = normalize(prompt)
        return fragments(of: systemPrompt).filter { normalizedPrompt.contains(normalize($0)) }
    }

    /// Последняя мера, если модель повторила копирование и после исправления: строки,
    /// которые почти целиком состоят из фраз инструкции, удаляются вместе с опустевшими тегами.
    static func removingEcho(from prompt: String, systemPrompt: String) -> String {
        let fragments = fragments(of: systemPrompt).map(normalize)
        let lines = prompt.components(separatedBy: "\n").filter { line in
            let content = normalize(strippingMarkup(line))
            guard !content.isEmpty else { return true }
            let echoedLength = fragments.filter { content.contains($0) }.map(\.count).reduce(0, +)
            return Double(echoedLength) < Double(content.count) * 0.6
        }
        return removingEmptyTags(lines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Фразы в «ёлочках» инструкция велит воспроизвести (например, «дай ссылки на источники»),
    /// поэтому они не считаются копированием.
    private static func fragments(of systemPrompt: String) -> [String] {
        systemPrompt
            .replacingOccurrences(of: #"«[^»]*»"#, with: "\n", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "\n.;!?—\""))
            .map { strippingMarkup($0).trimmingCharacters(in: CharacterSet(charactersIn: " ,-*()").union(.whitespaces)) }
            .filter { $0.split(separator: " ").count >= 4 && $0.count >= 20 }
    }

    private static func strippingMarkup(_ text: String) -> String {
        text.replacingOccurrences(of: #"</?[a-z_]+>|^\s*[-*•#\d.)]+\s*|\*\*"#, with: " ", options: .regularExpression)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: #"[\s,]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func removingEmptyTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?m)^\s*<([a-z_]+)>\s*</\1>\s*\n?"#, with: "", options: .regularExpression)
    }
}
