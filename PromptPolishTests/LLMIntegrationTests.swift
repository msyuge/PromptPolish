import XCTest
@testable import PromptPolish

/// Реальная генерация на модели. Запускается только через `make integration`:
/// при первом запуске скачивает веса, дальше работает офлайн. Отчёт — build/integration-output.txt.
final class LLMIntegrationTests: XCTestCase {
    private static let samples: [(String, ChatTarget)] = [
        ("напиши пост для телеграм-канала о том, как выбрать кофемолку для дома", .generic),
        ("объясни что такое замыкания в swift новичку", .claude),
        ("объясни что такое замыкания в swift новичку", .chatGPT),
        ("сравни тарифы мобильных операторов в россии", .gemini),
        ("какие новости про apple vision pro", .perplexity),
        ("найди ошибку в алгоритме сортировки пузырьком на python", .deepSeek),
        ("что сейчас обсуждают про spacex", .grok),
        ("напиши письмо клиенту о переносе срока сдачи проекта на неделю", .copilot),
        ("summarize this article for my boss", .mistral),
        ("сделай план", .generic),
        ("сделай промпт для ассистента, чтобы он добавил в мою macOS-утилиту меню «Системные инструкции» с редактированием", .claude),
        ("Перенести системные инструкции в настройки", .claude),
        ("explain swift closures to a beginner", .claude),
        ("write a cover letter for a junior designer job", .chatGPT),
        ("напиши пост", .generic),
        ("помоги улучшить мой проект", .claude),
        ("add dark mode to my app", .chatGPT),
    ]

    /// Размытые идеи, на которые модель должна задать вопросы, а не гадать.
    private static let vague: Set<String> = [
        "сделай план", "Перенести системные инструкции в настройки", "напиши пост", "помоги улучшить мой проект", "add dark mode to my app",
    ]

    /// Правдоподобные ответы на уточняющие вопросы для каждой идеи.
    private static let answers: [String: String] = [
        "напиши пост для телеграм-канала о том, как выбрать кофемолку для дома": "Канал для любителей кофе, текстовый пост на 1500 знаков, тон дружелюбный.",
        "объясни что такое замыкания в swift новичку": "Новичок знает основы Swift: переменные, функции, циклы.",
        "напиши пост": "Пост для телеграм-канала о кофе: как выбрать зерно для дома, 1000 знаков.",
        "помоги улучшить мой проект": "Это сайт-визитка фотографа на Tilda, хочу больше заявок от клиентов.",
        "add dark mode to my app": "It's a SwiftUI iOS app with about 20 screens; colors are hardcoded.",
        "какие новости про apple vision pro": "За последний месяц, официальные источники и крупные техсайты.",
        "summarize this article for my boss": "The boss is a CTO, wants 5 bullet points, the article text will be pasted after the prompt.",
        "Перенести системные инструкции в настройки": "Это моя macOS-утилита на SwiftUI: редактор системных инструкций сейчас в отдельном окне, его нужно перенести во вкладку окна настроек.",
        "сравни тарифы мобильных операторов в россии": "МТС, Билайн, МегаФон, Т2; тарифы до 800 рублей; интернет и звонки.",
        "найди ошибку в алгоритме сортировки пузырьком на python": "Код вставлю после промпта, ошибка в том, что список сортируется не полностью.",
        "что сейчас обсуждают про spacex": "За последнюю неделю, главное про Starship.",
        "напиши письмо клиенту о переносе срока сдачи проекта на неделю": "Причина — задержка у подрядчика, тон вежливый, клиент давний.",
        "сделай план": "План изучения основ Swift за месяц, по часу в день, для себя.",
    ]

    private var isEnabled: Bool { ProcessInfo.processInfo.environment["PROMPTPOLISH_INTEGRATION"] == "1" }

    /// Модель для прогона: `make integration MODEL=mlx-community/...` или `MODEL=apple/foundation-model`,
    /// по умолчанию — модель приложения. Выбирается так же, как в приложении.
    private var choice: ModelChoice {
        let id = ProcessInfo.processInfo.environment["PROMPTPOLISH_MODEL"].flatMap { $0.isEmpty ? nil : $0 }
        let status = AppleIntelligence.status
        let catalog = ModelCatalog.build(local: ModelLocator.standard.scan(), physicalMemory: ProcessInfo.processInfo.physicalMemory, appleIntelligence: status)
        return ModelCatalog.resolve(selectedID: id, installed: catalog.installed, downloads: catalog.downloads)
    }

    func testGeneratesPromptsOrQuestions() async throws {
        try XCTSkipUnless(isEnabled, "Интеграционный тест: запустите make integration")
        let builder = try PromptBuilder.bundled()
        let choice = choice
        let engine = PromptEngines.make(for: choice)

        let loadStart = ContinuousClock.now
        try await engine.prepare { _ in }
        var report = "Модель: \(choice.id) (\(choice.locationDescription))\nЗагрузка: \(ContinuousClock.now - loadStart)\n"

        var askedOnVague = 0
        var askedOnClear = 0
        // Повторяет сценарий ImproveCoordinator: вопросы → ответы → исправление дефектов промпта.
        for (rawIdea, target) in Self.samples {
            let idea = IdeaNormalizer.stripPromptRequest(rawIdea)
            var turns = builder.messages(for: idea, target: target)
            let systemPrompt = builder.systemPrompt(for: target, language: PromptLanguage.of(idea))
            var last = try await run(engine, turns)
            report += "\n=== [\(target.rawValue)] \(rawIdea)\n"
            if idea != rawIdea { report += "(идея без обращения к утилите: \(idea))\n" }
            report += describe(last)
            XCTAssertGreaterThan(last.chunks, 1, "Ожидался стриминг несколькими кусками")

            if case .questions = last.reply {
                if Self.vague.contains(rawIdea) { askedOnVague += 1 } else { askedOnClear += 1 }
                turns = builder.followUp(turns, questions: last.raw, answers: Self.answers[rawIdea] ?? "Сам реши, что разумно, и сразу напиши промпт.")
                last = try await run(engine, turns)
                report += "--- после ответов:\n" + describe(last)
                XCTAssertEqual(last.reply.isPrompt, true, "После ответов модель снова спросила: \(rawIdea)")
            }
            for _ in 0..<PromptQuality.maxCorrections {
                guard case let .prompt(text) = last.reply else { break }
                let issues = PromptQuality.issues(in: text, idea: idea, systemPrompt: systemPrompt)
                guard !issues.isEmpty else { break }
                report += "--- дефекты \(issues), исправление:\n"
                if !issues.contains(.degenerate) {
                    turns = builder.correcting(turns, reply: last.raw, issues: issues)
                }
                last = try await run(engine, turns)
                report += describe(last)
            }
            if case let .prompt(text) = last.reply {
                let remaining = PromptQuality.issues(in: text, idea: idea, systemPrompt: systemPrompt)
                if !remaining.isEmpty { report += "--- осталось после исправлений: \(remaining)\n" }
                let final = remaining.isEmpty ? text : PromptQuality.removingDefects(from: text, systemPrompt: systemPrompt, idea: idea)
                XCTAssertFalse(MetaPromptDetector.isMetaPrompt(final, idea: idea), "Мета-промпт для «\(rawIdea)» [\(target.rawValue)]")
                // Строки, которые почти целиком пересказывают инструкцию, недопустимы; отдельные совпавшие обороты — допустимы.
                XCTAssertEqual(PromptQuality.mostlyEchoedLines(in: final, systemPrompt: systemPrompt, idea: idea), [], "Пересказ инструкции для «\(rawIdea)»")
                XCTAssertFalse(PromptQuality.isDegenerate(final), "Пустой или зацикленный промпт для «\(rawIdea)» [\(target.rawValue)]")
                report += "--- алфавит: идея \(Script.dominant(in: idea)), промпт \(Script.dominant(in: final))\n"
                XCTAssertFalse(PromptQuality.isWrongLanguage(final, idea: idea), "Промпт не на языке идеи для «\(rawIdea)» [\(target.rawValue)]")
            }
        }

        report += "\n=== Вопросы: на размытые идеи \(askedOnVague) из \(Self.vague.count), на ясные \(askedOnClear) из \(Self.samples.count - Self.vague.count)\n"
        XCTAssertGreaterThanOrEqual(askedOnVague, Self.vague.count - 2, "Модель не переспрашивает на размытые идеи")

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/integration-output.txt")
        try report.write(to: output, atomically: true, encoding: .utf8)
    }

    /// Кнопка «Уточнить»: промпт готов, пользователь просит уточнить — модель должна задать вопросы.
    func testClarifyAfterPromptLeadsToQuestions() async throws {
        try XCTSkipUnless(isEnabled)
        let builder = try PromptBuilder.bundled()
        let engine = PromptEngines.make(for: choice)
        try await engine.prepare { _ in }

        for (idea, target) in [("объясни что такое замыкания в swift новичку", ChatTarget.claude), ("write a cover letter for a junior designer job", .chatGPT)] {
            let turns = builder.messages(for: idea, target: target)
            let first = try await run(engine, turns)
            guard case .prompt = first.reply else { continue }
            let clarify = try await run(engine, builder.requestingQuestions(turns, reply: first.raw))
            guard case .questions = clarify.reply else {
                return XCTFail("После «Уточнить» модель не задала вопросов для «\(idea)»: \(clarify.raw.prefix(200))")
            }
        }
    }

    func testCancellationStopsGeneration() async throws {
        try XCTSkipUnless(isEnabled)
        let engine = PromptEngines.make(for: choice)
        try await engine.prepare { _ in }

        var chunks = 0
        let turns = PromptBuilder(systemPrompt: "Ты помощник.").messages(for: "напиши подробный план изучения swift на год")
        for try await _ in engine.respond(to: turns) {
            chunks += 1
            if chunks == 3 { break }
        }
        XCTAssertEqual(chunks, 3)
        // Следующая генерация на том же движке ждёт, пока отменённая полностью остановится, и работает нормально.
        var after = ""
        for try await chunk in engine.respond(to: PromptBuilder(systemPrompt: "Отвечай одним словом.").messages(for: "столица франции")) {
            after += chunk
        }
        XCTAssertFalse(PromptQuality.isDegenerate(after + " и ещё немного текста для проверки"), "После отмены модель выдаёт мусор: \(after)")
    }

    private struct Run {
        let raw: String
        let reply: ModelReply
        let chunks: Int
        let duration: Duration
    }

    private func run(_ engine: any PromptEngine, _ turns: [ChatTurn]) async throws -> Run {
        let start = ContinuousClock.now
        var raw = ""
        var chunks = 0
        for try await chunk in engine.respond(to: turns) {
            raw += chunk
            chunks += 1
            if PromptQuality.isLooping(raw) { break }
        }
        return Run(raw: raw, reply: ModelReply.parse(raw), chunks: chunks, duration: ContinuousClock.now - start)
    }

    private func describe(_ run: Run) -> String {
        let fenced = ModelReply.fencedBlock(in: run.raw) != nil
        switch run.reply {
        case let .prompt(text):
            return "[промт, блок ```: \(fenced)]\n\(text)\n--- чанков: \(run.chunks), время: \(run.duration)\n"
        case let .questions(text):
            return "[вопросы]\n\(text)\n--- чанков: \(run.chunks), время: \(run.duration)\n"
        }
    }
}

private extension ModelReply {
    var isPrompt: Bool {
        if case .prompt = self { return true }
        return false
    }
}
