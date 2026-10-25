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
    ]

    /// Правдоподобные ответы на уточняющие вопросы для каждой идеи.
    private static let answers: [String: String] = [
        "напиши пост для телеграм-канала о том, как выбрать кофемолку для дома": "Канал для любителей кофе, текстовый пост на 1500 знаков, тон дружелюбный.",
        "объясни что такое замыкания в swift новичку": "Новичок знает основы Swift: переменные, функции, циклы.",
        "какие новости про apple vision pro": "За последний месяц, официальные источники и крупные техсайты.",
        "summarize this article for my boss": "The boss is a CTO, wants 5 bullet points, the article text will be pasted after the prompt.",
        "сравни тарифы мобильных операторов в россии": "МТС, Билайн, МегаФон, Т2; тарифы до 800 рублей; интернет и звонки.",
        "найди ошибку в алгоритме сортировки пузырьком на python": "Код вставлю после промпта, ошибка в том, что список сортируется не полностью.",
        "что сейчас обсуждают про spacex": "За последнюю неделю, главное про Starship.",
        "напиши письмо клиенту о переносе срока сдачи проекта на неделю": "Причина — задержка у подрядчика, тон вежливый, клиент давний.",
        "сделай план": "План изучения основ Swift за месяц, по часу в день, для себя.",
    ]

    private var isEnabled: Bool { ProcessInfo.processInfo.environment["PROMPTPOLISH_INTEGRATION"] == "1" }

    /// Модель для прогона: `make integration MODEL=mlx-community/...`, по умолчанию — модель приложения.
    /// Выбирается так же, как в приложении: копия на диске, иначе скачивание.
    private var spec: ModelSpec {
        let id = ProcessInfo.processInfo.environment["PROMPTPOLISH_MODEL"].flatMap { $0.isEmpty ? nil : $0 }
        let catalog = ModelCatalog.build(local: ModelLocator.standard.scan(), physicalMemory: ProcessInfo.processInfo.physicalMemory)
        return ModelSpec(for: ModelCatalog.resolve(selectedID: id, installed: catalog.installed, downloads: catalog.downloads))
    }

    func testGeneratesPromptsOrQuestions() async throws {
        try XCTSkipUnless(isEnabled, "Интеграционный тест: запустите make integration")
        let builder = try PromptBuilder.bundled()
        let engine = LLMEngine(spec: spec)

        let loadStart = ContinuousClock.now
        try await engine.prepare()
        var report = "Модель: \(engine.spec.id) (\(engine.spec.directory?.path(percentEncoded: false) ?? "скачивание"))\nЗагрузка: \(ContinuousClock.now - loadStart)\n"

        // Повторяет сценарий ImproveCoordinator: вопросы → ответы → одно исправление дефектов промпта.
        for (rawIdea, target) in Self.samples {
            let idea = IdeaNormalizer.stripPromptRequest(rawIdea)
            var turns = builder.messages(for: idea, target: target)
            let systemPrompt = builder.systemPrompt(for: target)
            var last = try await run(engine, turns)
            report += "\n=== [\(target.rawValue)] \(rawIdea)\n"
            if idea != rawIdea { report += "(идея без обращения к утилите: \(idea))\n" }
            report += describe(last)
            XCTAssertGreaterThan(last.chunks, 1, "Ожидался стриминг несколькими кусками")

            if case .questions = last.reply {
                turns = builder.followUp(turns, questions: last.raw, answers: Self.answers[rawIdea] ?? "Сам реши, что разумно, и сразу напиши промпт.")
                last = try await run(engine, turns)
                report += "--- после ответов:\n" + describe(last)
                XCTAssertEqual(last.reply.isPrompt, true, "После ответов модель снова спросила: \(rawIdea)")
            }
            if case let .prompt(text) = last.reply {
                let issues = PromptQuality.issues(in: text, idea: idea, systemPrompt: systemPrompt)
                if !issues.isEmpty {
                    report += "--- дефекты \(issues), исправление:\n"
                    turns = builder.correcting(turns, reply: last.raw, issues: issues)
                    last = try await run(engine, turns)
                    report += describe(last)
                }
            }
            if case let .prompt(text) = last.reply {
                let remaining = PromptQuality.issues(in: text, idea: idea, systemPrompt: systemPrompt)
                XCTAssertFalse(remaining.contains(.metaTask), "Мета-промпт для «\(rawIdea)» [\(target.rawValue)]")
                let cleaned = PromptQuality.removingEcho(from: text, systemPrompt: systemPrompt)
                XCTAssertTrue(PromptQuality.echoedFragments(in: cleaned, systemPrompt: systemPrompt).isEmpty, "Копия каркаса для «\(rawIdea)»")
                if !remaining.isEmpty { report += "--- осталось после исправления: \(remaining)\n" }
            }
        }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/integration-output.txt")
        try report.write(to: output, atomically: true, encoding: .utf8)
    }

    func testCancellationStopsGeneration() async throws {
        try XCTSkipUnless(isEnabled)
        let engine = LLMEngine(spec: spec)
        try await engine.prepare()

        var chunks = 0
        let turns = PromptBuilder(systemPrompt: "Ты помощник.").messages(for: "напиши подробный план изучения swift на год")
        for try await _ in engine.respond(to: turns) {
            chunks += 1
            if chunks == 3 { break }
        }
        XCTAssertEqual(chunks, 3)
    }

    private struct Run {
        let raw: String
        let reply: ModelReply
        let chunks: Int
        let duration: Duration
    }

    private func run(_ engine: LLMEngine, _ turns: [ChatTurn]) async throws -> Run {
        let start = ContinuousClock.now
        var raw = ""
        var chunks = 0
        for try await chunk in engine.respond(to: turns) {
            raw += chunk
            chunks += 1
        }
        return Run(raw: raw, reply: ModelReply.parse(raw), chunks: chunks, duration: ContinuousClock.now - start)
    }

    private func describe(_ run: Run) -> String {
        let fenced = ModelReply.fencedBlock(in: run.raw) != nil
        switch run.reply {
        case let .prompt(text):
            XCTAssertFalse(text.isEmpty)
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
