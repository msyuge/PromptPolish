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

/// Маленькая модель сама плохо понимает, что ей чего-то не хватает, и додумывает. Короткая идея или
/// ссылка на неизвестный ей контекст («мой проект», «my app») — повод подсказать, что лучше переспросить.
enum IdeaClarity {
    private static let ownContext: Set<String> = [
        "мой", "моя", "моё", "мое", "мою", "мои", "моего", "моей", "моих", "моим", "моему", "моём", "моем", "моими",
        "наш", "наша", "наше", "нашу", "наши", "нашего", "нашей", "наших", "нашим", "нашему", "нашем",
        "my", "our",
    ]

    static func needsClarification(_ idea: String) -> Bool {
        let words = idea.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if words.count <= 5 { return true }
        // Длинная идея со своим описанием или вставленным материалом — контекст уже есть.
        return words.count <= 20 && words.contains(where: ownContext.contains)
    }
}

/// Дефекты готового промпта, которые исправляются повторным запросом к модели.
enum PromptIssue: Equatable {
    /// Промпт просит чат написать промпт вместо того, чтобы поставить ему задачу.
    case metaTask
    /// В промпт переписаны или пересказаны фразы из системной инструкции (описания разделов и правила).
    case templateEcho([String])
    /// XML-теги разделов не закрыты или закрыты без открытия.
    case brokenTags([String])
    /// Ответ пустой или зациклился: одна и та же строка повторяется много раз.
    case degenerate
    /// Промпт написан не тем алфавитом, что идея (русская идея — английский промпт и наоборот).
    case wrongLanguage
}

/// Алфавит текста. Определитель языка ошибается на коротких фразах (русскую идею про тарифы считает
/// казахской), а сравнение алфавитов надёжно отличает главный случай — русскую идею и английский промпт.
enum Script: Equatable {
    case cyrillic
    case latin
    case other

    /// Преобладающий алфавит без XML-тегов и кода: имена тегов разделов остаются английскими в любом промпте.
    static func dominant(in text: String) -> Script {
        let plain = text
            .replacingOccurrences(of: #"(?s)```.*?```"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"</?[a-z_]+>"#, with: " ", options: .regularExpression)
        var cyrillic = 0
        var latin = 0
        for scalar in plain.unicodeScalars where CharacterSet.letters.contains(scalar) {
            if (0x0400...0x04FF).contains(scalar.value) { cyrillic += 1 } else if scalar.isASCII { latin += 1 }
        }
        guard cyrillic + latin >= 10 else { return .other }
        if Double(cyrillic) >= Double(cyrillic + latin) * 0.6 { return .cyrillic }
        if Double(latin) >= Double(cyrillic + latin) * 0.8 { return .latin }
        return .other
    }
}

enum PromptQuality {
    /// Сколько раз подряд модель просят исправить один и тот же промпт.
    static let maxCorrections = 2

    /// Совпадение по стольким словам подряд с инструкцией не бывает случайным (5 давало ложные срабатывания
    /// на естественных фразах вроде «формат ответа: таблица со столбцами»):
    /// модель переписала или пересказала её вместо того, чтобы заполнить разделы содержанием.
    private static let shingleLength = 6

    static func issues(in prompt: String, idea: String, systemPrompt: String) -> [PromptIssue] {
        var issues: [PromptIssue] = []
        if MetaPromptDetector.isMetaPrompt(prompt, idea: idea) {
            issues.append(.metaTask)
        }
        let echoed = echoedFragments(in: prompt, systemPrompt: systemPrompt, idea: idea)
        if !echoed.isEmpty {
            issues.append(.templateEcho(echoed))
        }
        let broken = brokenTags(in: prompt)
        if !broken.isEmpty {
            issues.append(.brokenTags(broken))
        }
        if isDegenerate(prompt) {
            issues.append(.degenerate)
        }
        if isWrongLanguage(prompt, idea: idea) {
            issues.append(.wrongLanguage)
        }
        return issues
    }

    /// Русская идея — английский промпт или английская идея — русский промпт.
    static func isWrongLanguage(_ prompt: String, idea: String) -> Bool {
        let expected = Script.dominant(in: idea)
        let actual = Script.dominant(in: prompt)
        return expected != .other && actual != .other && expected != actual
    }

    /// Строка, повторённая столько раз, — признак зацикливания маленькой модели.
    private static let loopThreshold = 6

    /// Генерация зациклилась: одна непустая строка повторилась 8 раз или фраза из 10 слов — 3 раза.
    /// Проверяется во время стриминга, чтобы не досчитывать петлю до лимита токенов.
    static func isLooping(_ raw: String) -> Bool {
        var counts: [Substring: Int] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let key = line.trimmingCharacters(in: .whitespaces)[...]
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
            if counts[key]! >= 8 { return true }
        }
        return hasRepeatedPhrase(raw)
    }

    /// Слов во фразе, повтор которой считается петлёй.
    private static let loopPhraseLength = 10

    /// Фраза из 10 слов встречается 3 раза. Так выглядит петля, в которой строки отличаются номером пункта
    /// («6. Не используй…», «7. Не используй…») или повторяется целый блок из нескольких строк.
    /// Цифры и знаки препинания не учитываются.
    static func hasRepeatedPhrase(_ text: String) -> Bool {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        guard words.count >= loopPhraseLength * 3 else { return false }
        var counts: [ArraySlice<String>: Int] = [:]
        for start in 0...(words.count - loopPhraseLength) {
            let phrase = words[start..<(start + loopPhraseLength)]
            counts[phrase, default: 0] += 1
            if counts[phrase]! >= 3 { return true }
        }
        return false
    }

    /// Меньше 20 букв, строка, повторённая 6 и более раз (пустые строки и ``` тоже считаются), или повтор фразы.
    static func isDegenerate(_ prompt: String) -> Bool {
        if prompt.unicodeScalars.filter(CharacterSet.letters.contains).count < 20 { return true }
        var counts: [String: Int] = [:]
        for line in prompt.components(separatedBy: "\n") {
            let key = line.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
            if counts[key]! >= loopThreshold { return true }
        }
        return hasRepeatedPhrase(prompt)
    }

    /// Куски промпта, совпадающие с инструкцией по 6 и более словам подряд (после нормализации).
    static func echoedFragments(in prompt: String, systemPrompt: String, idea: String = "") -> [String] {
        let tokens = tokenize(prompt)
        let marked = echoMarks(tokens, systemPrompt: systemPrompt, idea: idea)
        var runs: [String] = []
        var current: [String] = []
        for (index, token) in tokens.enumerated() {
            if marked[index] {
                current.append(token.word)
            } else if !current.isEmpty {
                runs.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { runs.append(current.joined(separator: " ")) }
        return runs
    }

    /// Теги разделов промпта Claude. Остальные теги (например, HTML в задаче про вёрстку) — содержание, а не структура.
    static let sectionTags: Set<String> = ["document", "role", "context", "task", "instructions", "constraints", "examples", "output_format"]

    /// Теги разделов (`<role>`, `<task>`…), у которых не сходятся открытие и закрытие. Код в ``` не проверяется.
    static func brokenTags(in prompt: String) -> [String] {
        var depth: [String: Int] = [:]
        var broken: Set<String> = []
        var inCode = false
        for line in prompt.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCode.toggle()
                continue
            }
            guard !inCode else { continue }
            let regex = try! NSRegularExpression(pattern: #"<(/?)([a-z_]+)>"#)
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let slash = Range(match.range(at: 1), in: line), let name = Range(match.range(at: 2), in: line) else { continue }
                let tag = String(line[name])
                guard sectionTags.contains(tag) else { continue }
                if line[slash].isEmpty {
                    depth[tag, default: 0] += 1
                } else if depth[tag, default: 0] > 0 {
                    depth[tag, default: 0] -= 1
                } else {
                    broken.insert(tag)
                }
            }
        }
        broken.formUnion(depth.filter { $0.value != 0 }.map(\.key))
        return broken.sorted()
    }

    /// Последняя мера, если дефекты остались и после исправлений: удаляются строки,
    /// которые больше чем наполовину пересказывают инструкцию или просят написать промпт.
    static func removingDefects(from prompt: String, systemPrompt: String, idea: String) -> String {
        // Повторы строк (зацикливание) схлопываются до первого вхождения; номер пункта и знаки не учитываются.
        var seen: Set<String> = []
        let unique = prompt.components(separatedBy: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let words = trimmed.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            let key = words.count >= 3 ? words.joined(separator: " ") : trimmed
            return trimmed.isEmpty || trimmed.hasPrefix("</") || seen.insert(key).inserted
        }
        let lines = unique.filter { line in
            if line.trimmingCharacters(in: .whitespaces) == "```" { return false }
            if MetaPromptDetector.isMetaPrompt(line, idea: idea) { return false }
            return !isMostlyEcho(line, systemPrompt: systemPrompt, idea: idea)
        }
        return removingEmptyTags(lines.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Строки, которые больше чем наполовину пересказывают инструкцию. Отдельный совпавший оборот в своей
    /// строке допустим: модель может разумно взять форму требования из примера.
    static func mostlyEchoedLines(in prompt: String, systemPrompt: String, idea: String) -> [String] {
        prompt.components(separatedBy: "\n").filter { isMostlyEcho($0, systemPrompt: systemPrompt, idea: idea) }
    }

    private static func isMostlyEcho(_ line: String, systemPrompt: String, idea: String) -> Bool {
        let tokens = tokenize(line)
        guard !tokens.isEmpty else { return false }
        let marked = echoMarks(tokens, systemPrompt: systemPrompt, idea: idea).filter { $0 }.count
        return Double(marked) >= Double(tokens.count) * 0.5
    }

    /// Отмечает слова, входящие в любую последовательность из 6 слов одной строки, которая есть в одной строке
    /// инструкции. Через перенос строки не склеивается: «# Role and goal» + «You are a…» — естественное начало промпта.
    /// Фразы в «ёлочках» инструкция велит воспроизвести (например, «дай ссылки на источники»),
    /// а слова из идеи пользователя — его собственные, поэтому они не считаются копированием.
    private static func echoMarks(_ tokens: [(word: String, line: Int)], systemPrompt: String, idea: String) -> [Bool] {
        let source = systemPrompt.replacingOccurrences(of: #"«[^»]*»"#, with: " | ", options: .regularExpression)
        let instruction = shingles(of: tokenize(source))
        let own = shingles(of: tokenize(idea))
        var marked = Array(repeating: false, count: tokens.count)
        guard tokens.count >= shingleLength else { return marked }
        for start in 0...(tokens.count - shingleLength) {
            let window = tokens[start..<(start + shingleLength)]
            guard window.first?.line == window.last?.line else { continue }
            let shingle = window.map(\.word).joined(separator: " ")
            if instruction.contains(shingle), !own.contains(shingle) {
                for index in start..<(start + shingleLength) { marked[index] = true }
            }
        }
        return marked
    }

    private static func shingles(of tokens: [(word: String, line: Int)]) -> Set<String> {
        guard tokens.count >= shingleLength else { return [] }
        var result: Set<String> = []
        for start in 0...(tokens.count - shingleLength) {
            let window = tokens[start..<(start + shingleLength)]
            guard window.first?.line == window.last?.line else { continue }
            result.insert(window.map(\.word).joined(separator: " "))
        }
        return result
    }

    /// Слова текста без разметки: теги, знаки и регистр не важны, «ё» равно «е».
    private static func tokenize(_ text: String) -> [(word: String, line: Int)] {
        text.components(separatedBy: "\n").enumerated().flatMap { index, line in
            line.replacingOccurrences(of: #"</?[a-z_]+>"#, with: " ", options: .regularExpression)
                .lowercased()
                .replacingOccurrences(of: "ё", with: "е")
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .map { (word: $0, line: index) }
        }
    }

    private static func removingEmptyTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?m)^\s*<([a-z_]+)>\s*</\1>\s*\n?"#, with: "", options: .regularExpression)
    }
}
