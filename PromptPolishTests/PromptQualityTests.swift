import XCTest
@testable import PromptPolish

final class IdeaNormalizerTests: XCTestCase {
    func testStripsRequestToTheUtility() {
        XCTAssertEqual(
            IdeaNormalizer.stripPromptRequest("сделай промпт для ассистента, чтобы он мог добавить меню «Системные инструкции»"),
            "Добавить меню «Системные инструкции»"
        )
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest("напиши мне подробный промт для анализа продаж за квартал"), "Анализа продаж за квартал")
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest("Write a prompt to summarize this article"), "Summarize this article")
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest("сделай промпт: объясни замыкания в Swift"), "Объясни замыкания в Swift")
    }

    func testKeepsIdeasThatAreNotRequestsToTheUtility() {
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest("объясни что такое замыкания"), "объясни что такое замыкания")
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest("как писать хорошие промпты"), "как писать хорошие промпты")
    }

    func testKeepsPromptsForGenerators() {
        let idea = "напиши промпт для midjourney: кот в скафандре на Марсе"
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest(idea), idea)
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest("сделай промт для генерации картинки с котом"), "сделай промт для генерации картинки с котом")
    }

    func testRequestWithoutTaskStaysAsIs() {
        XCTAssertEqual(IdeaNormalizer.stripPromptRequest("сделай промпт"), "сделай промпт")
    }
}

final class PromptQualityTests: XCTestCase {
    private let claudeSystemPrompt = """
    2. Всегда оформляй итоговый промпт в одно окно кода (markdown block ```).
    3. Claude лучше всего понимает разделы в XML-тегах. Собери промпт из таких разделов, в этом порядке.
    - <role> — конкретная экспертиза, нужная для этой задачи;
    - <context> — зачем нужна задача, для кого результат, что уже известно;
    - <output_format> — точная форма ответа: структура, длина, оформление.
    5. Если для задачи нужен текст, документ или код пользователя, добавь в начало промпта тег <document></document>, в который пользователь вставит материал.
    Последний пункт «дай ссылки на источники в одном списке».
    """

    /// Реальный ответ модели, который прошёл прошлую проверку: пересказ правил, мета-просьба и сломанные теги.
    private let realDefectivePrompt = """
    <role>
    > Специалист по внедрению и настройке системных инструкций.
    <context>
    Задача пользователя: Перенести системные инструкции в настройки.
    </instructions>
    <constraints>
    - <user_input> : Собрать промпт в одно окно кода (markdown block ```).
    - <document> : Если требуется текст, документ или код, добавить в начало промпта тег <document></document>, в который пользователь вставит материал.
    </task>
    <output_format>
    Напиши промпт для этого случая:
    </output_format>
    """

    func testCatchesParaphrasedRulesMetaRequestAndBrokenTagsInRealOutput() {
        let issues = PromptQuality.issues(in: realDefectivePrompt, idea: "Перенести системные инструкции в настройки", systemPrompt: claudeSystemPrompt)

        XCTAssertTrue(issues.contains(.metaTask))
        guard case let .templateEcho(echoed)? = issues.first(where: { if case .templateEcho = $0 { true } else { false } }) else {
            return XCTFail("Пересказ правил не найден: \(issues)")
        }
        XCTAssertTrue(echoed.contains { $0.contains("в одно окно кода markdown block") })
        XCTAssertTrue(echoed.contains { $0.contains("в начало промпта тег") && $0.contains("пользователь вставит материал") })
        guard case let .brokenTags(tags)? = issues.first(where: { if case .brokenTags = $0 { true } else { false } }) else {
            return XCTFail("Сломанные теги не найдены: \(issues)")
        }
        XCTAssertTrue(tags.contains("role"))
        XCTAssertTrue(tags.contains("instructions"))
        XCTAssertTrue(tags.contains("task"))
    }

    func testDetectsCopiedSectionDescriptions() {
        let prompt = """
        <role>Конкретная экспертиза, нужная для этой задачи.</role>
        <task>Добавь в утилиту меню «Системные инструкции».</task>
        """

        let echoed = PromptQuality.echoedFragments(in: prompt, systemPrompt: claudeSystemPrompt)

        XCTAssertEqual(echoed, ["конкретная экспертиза нужная для этой задачи"])
    }

    func testFilledPromptIsClean() {
        let prompt = """
        <role>Senior macOS-разработчик, SwiftUI и AppKit.</role>
        <context>Утилита в строке меню улучшает промпты; нужен редактор инструкций в настройках.</context>
        <task>Перенеси редактор системных инструкций из отдельного окна во вкладку настроек.</task>
        <output_format>Код изменённых файлов и короткое пояснение.</output_format>
        """
        XCTAssertEqual(PromptQuality.issues(in: prompt, idea: "перенеси системные инструкции в настройки", systemPrompt: claudeSystemPrompt), [])
    }

    func testQuotedPhrasesAndIdeaWordsAreAllowed() {
        XCTAssertEqual(PromptQuality.echoedFragments(in: "Учти:\n- дай ссылки на источники в одном списке.", systemPrompt: claudeSystemPrompt), [])
        let idea = "нужна точная форма ответа структура длина оформление для отчёта"
        XCTAssertEqual(PromptQuality.echoedFragments(in: "Точная форма ответа: структура, длина, оформление.", systemPrompt: claudeSystemPrompt, idea: idea), [])
    }

    func testCodeAndDocumentTagsAreBalancedChecks() {
        XCTAssertEqual(PromptQuality.brokenTags(in: "<document>\n</document>\n<task>Сделай.</task>"), [])
        XCTAssertEqual(PromptQuality.brokenTags(in: "<task>Объясни код:\n```html\n<div>\n```\n</task>"), [])
        XCTAssertEqual(PromptQuality.brokenTags(in: "<task>Сделай.\n<role>Эксперт.</role>"), ["task"])
    }

    func testRemovingDefectsDropsEchoAndMetaLines() {
        let prompt = """
        <role>Конкретная экспертиза, нужная для этой задачи.</role>
        <task>Добавь в утилиту меню «Системные инструкции».</task>
        <output_format>
        Напиши промпт для этого случая:
        </output_format>
        """

        let cleaned = PromptQuality.removingDefects(from: prompt, systemPrompt: claudeSystemPrompt, idea: "добавь меню")

        XCTAssertEqual(cleaned, "<task>Добавь в утилиту меню «Системные инструкции».</task>")
    }

    func testCorrectionMessageNamesTheProblems() {
        let builder = PromptBuilder(systemPrompt: "S")
        let history = builder.messages(for: "идея")

        let next = builder.correcting(history, reply: "ответ", issues: [.metaTask, .templateEcho(["зачем нужна задача для кого результат"]), .brokenTags(["role"])])

        XCTAssertEqual(next[2], ChatTurn(role: .assistant, content: "ответ"))
        XCTAssertTrue(next[3].content.hasPrefix("Исправь промпт:"))
        XCTAssertTrue(next[3].content.contains("промпт просит написать промпт"))
        XCTAssertTrue(next[3].content.contains("«зачем нужна задача для кого результат»"))
        XCTAssertTrue(next[3].content.contains("<role>"))
    }

    func testBundledChatPromptsHaveNoCopyableSkeleton() throws {
        let builder = try PromptBuilder.bundled()
        for target in ChatTarget.allCases where target != .generic {
            for language in PromptLanguage.allCases {
            // Блок кода допустим только в примере хорошего ответа, но не в правилах со структурой.
            let prompt = builder.systemPrompt(for: target, language: language)
            let rules = prompt.components(separatedBy: language == .ru ? "\nПример." : "\nExample.")[0]
            XCTAssertFalse(rules.contains("```\n<"), "\(target): каркас в блоке кода")
            XCTAssertFalse(rules.contains("```\n#"), "\(target): каркас в блоке кода")
            let noCopy = language == .ru ? "пиши содержание задачи пользователя, а не описание" : "write the user's content, not the description"
            XCTAssertTrue(prompt.contains(noCopy) || target == .perplexity, "\(target)-\(language): нет запрета копировать описания")
            }
        }
    }

    func testDegenerateRepliesAreDetected() {
        XCTAssertTrue(PromptQuality.isDegenerate(""))
        XCTAssertTrue(PromptQuality.isDegenerate("```\n```"))
        XCTAssertTrue(PromptQuality.isDegenerate(Array(repeating: "```", count: 40).joined(separator: "\n")))
        XCTAssertTrue(PromptQuality.isDegenerate("Задача: напиши пост.\n" + Array(repeating: "- кофе", count: 6).joined(separator: "\n")))
        XCTAssertFalse(PromptQuality.isDegenerate("Задача: напиши пост про кофе для телеграм-канала.\n- тон дружелюбный\n- 1500 знаков"))
    }

    func testRemovingDefectsCollapsesLoops() {
        let looped = "Задача: напиши пост про кофе для канала.\n" + Array(repeating: "- кофе", count: 8).joined(separator: "\n") + "\n```\n```"

        let cleaned = PromptQuality.removingDefects(from: looped, systemPrompt: "S", idea: "пост про кофе")

        XCTAssertEqual(cleaned, "Задача: напиши пост про кофе для канала.\n- кофе")
        XCTAssertFalse(PromptQuality.isDegenerate(cleaned))
    }

    func testEveryInstructionHasExamplesOfPromptAndQuestions() throws {
        let builder = try PromptBuilder.bundled()
        for target in ChatTarget.allCases {
            for language in PromptLanguage.allCases {
            let prompt = builder.systemPrompt(for: target, language: language)
            let ru = language == .ru
            XCTAssertTrue(prompt.contains(ru ? "\nПример. Он показывает только форму" : "\nExample. It shows only the shape"), "\(target)-\(language): нет примера промпта")
            XCTAssertTrue(prompt.contains(ru ? "а не из примера" : "never from the example"), "\(target)-\(language): нет запрета копировать пример")
            XCTAssertTrue(prompt.contains("\(language.questionsMarker)\n1."), "\(target)-\(language): нет примера вопросов")
            guard case let .prompt(example) = ModelReply.parse(prompt.components(separatedBy: ru ? "Ответ:\n" : "Reply:\n")[1]) else {
                return XCTFail("\(target): пример не разбирается как промпт")
            }
            XCTAssertTrue(PromptQuality.brokenTags(in: example).isEmpty, "\(target): в примере сломаны теги")
            XCTAssertFalse(PromptQuality.isDegenerate(example), "\(target): пример слишком короткий")
            }
        }
    }

    func testNaturalFiveWordPhraseIsNotEcho() {
        let system = "**Формат ответа:** таблица со столбцами «модель», «цена», под ней рекомендация."
        let prompt = "**Формат ответа:** таблица со столбцами «оператор», «тариф», «цена»."
        XCTAssertEqual(PromptQuality.echoedFragments(in: prompt, systemPrompt: system), [])
    }

    func testWrongLanguageIsDetectedByScript() {
        let idea = "сравни тарифы мобильных операторов в россии"

        XCTAssertTrue(PromptQuality.isWrongLanguage("Task: compare mobile plans in Russia.\nRequirements:\n- price", idea: idea))
        XCTAssertFalse(PromptQuality.isWrongLanguage("<task>Сравни тарифы мобильных операторов.</task>\n<output_format>Таблица.</output_format>", idea: idea))
        XCTAssertTrue(PromptQuality.isWrongLanguage("Задача: кратко перескажи статью.", idea: "summarize this article for my boss"))
        XCTAssertFalse(PromptQuality.isWrongLanguage("Summarize the article below in 5 bullet points.", idea: "summarize this article for my boss"))
        XCTAssertTrue(PromptQuality.issues(in: "Task: compare mobile plans in Russia, with prices.", idea: idea, systemPrompt: "S").contains(.wrongLanguage))
    }

    func testWrongLanguageCorrectionNamesLanguageInBothLanguages() {
        let builder = PromptBuilder(systemPrompt: "S")
        let history = builder.messages(for: "сравни тарифы мобильных операторов")

        let next = builder.correcting(history, reply: "Task: compare plans.", issues: [.wrongLanguage])

        XCTAssertTrue(next[3].content.contains("перепиши весь промпт на языке: русский"))
        let english = builder.correcting(builder.messages(for: "compare mobile plans"), reply: "Задача: сравни.", issues: [.wrongLanguage])
        XCTAssertTrue(english[3].content.contains("rewrite the whole prompt in English"))
    }

    func testVagueIdeasNeedClarification() {
        XCTAssertTrue(IdeaClarity.needsClarification("сделай план"))
        XCTAssertTrue(IdeaClarity.needsClarification("Перенести системные инструкции в настройки"))
        XCTAssertTrue(IdeaClarity.needsClarification("помоги улучшить мой проект"))
        XCTAssertTrue(IdeaClarity.needsClarification("add dark mode to my app"))
        XCTAssertFalse(IdeaClarity.needsClarification("объясни что такое замыкания в swift новичку"))
        XCTAssertFalse(IdeaClarity.needsClarification("напиши письмо клиенту о переносе срока сдачи проекта на неделю"))
        XCTAssertFalse(IdeaClarity.needsClarification("помоги мне выбрать ноутбук до 80 тысяч для программирования"))
    }

    func testVagueIdeaGetsHintInRequest() {
        let builder = PromptBuilder(systemPrompt: "S")

        XCTAssertTrue(builder.messages(for: "сделай план")[1].content.contains("идея требует уточнения"))
        XCTAssertTrue(builder.messages(for: "add dark mode to my app")[1].content.contains("the idea needs clarification"))
        XCTAssertFalse(builder.messages(for: "объясни что такое замыкания в swift новичку")[1].content.contains("требует уточнения"))
    }

    func testClarifyRequestAsksForQuestionsInIdeaLanguage() {
        let builder = PromptBuilder(systemPrompt: "S")

        let ru = builder.requestingQuestions(builder.messages(for: "перенести инструкции в настройки"), reply: "```\nПромпт\n```")
        let en = builder.requestingQuestions(builder.messages(for: "add dark mode to my app"), reply: "```\nPrompt\n```")

        XCTAssertEqual(ru[2], ChatTurn(role: .assistant, content: "```\nПромпт\n```"))
        XCTAssertTrue(ru[3].content.contains("«ВОПРОСЫ:»"))
        XCTAssertTrue(ru[3].content.contains("Промпт пока не пиши"))
        XCTAssertTrue(en[3].content.contains("\"QUESTIONS:\""))
    }

    func testEchoDoesNotSpanLines() {
        let system = "# Role and goal\nYou are a naming specialist. I need a name for a small yoga studio."
        let prompt = "# Role and goal\nYou are a career coach who helps junior designers."
        XCTAssertEqual(PromptQuality.echoedFragments(in: prompt, systemPrompt: system), [])
        XCTAssertFalse(PromptQuality.echoedFragments(in: "You are a naming specialist. I need a name for my bakery.", systemPrompt: system).isEmpty)
    }

    func testLoopingIsDetectedDuringStreaming() {
        XCTAssertTrue(PromptQuality.isLooping("Задача: объясни.\n" + Array(repeating: "```", count: 8).joined(separator: "\n")))
        XCTAssertFalse(PromptQuality.isLooping("Задача: объясни.\n" + Array(repeating: "```", count: 7).joined(separator: "\n")))
        XCTAssertFalse(PromptQuality.isLooping("- пункт один\n- пункт два\n- пункт три"))
    }

    func testHTMLInsidePromptIsNotBrokenStructure() {
        let prompt = "<task>Добавь тёмную тему.</task>\nВот разметка:\n<html><body><script>"
        XCTAssertEqual(PromptQuality.brokenTags(in: prompt), [])
    }

    func testLoopWithNumberedLinesIsDetected() {
        let items = (1...4).map { "\($0). Не используй сложные термины без объяснения и примеров из реальной жизни." }
        let raw = "<constraints>\n" + items.joined(separator: "\n")
        XCTAssertTrue(PromptQuality.isLooping(raw))
        XCTAssertTrue(PromptQuality.isDegenerate(raw))
    }

    func testLoopOfMultilineBlockIsDetected() {
        let block = "Роль: ты эксперт по кофе.\nЗадача: объясни, как выбрать кофемолку для дома.\n"
        XCTAssertTrue(PromptQuality.isLooping("Начало.\n" + String(repeating: block, count: 3)))
    }

    func testLongNormalPromptIsNotLooping() {
        let prompt = """
        Роль: ты опытный бариста и автор телеграм-канала о кофе.
        Задача: напиши пост о том, как выбрать кофемолку для дома.
        Контекст: читатели — новички, у них капельная кофеварка и турка.
        Ограничения:
        1. Не используй сложные термины без объяснения.
        2. Не советуй конкретные магазины.
        3. Объём — до 1500 знаков.
        Формат ответа: заголовок, три коротких абзаца и вывод одним предложением.
        """
        XCTAssertFalse(PromptQuality.isLooping(prompt))
        XCTAssertFalse(PromptQuality.isDegenerate(prompt))
    }

    func testNumberedLoopIsCollapsed() {
        let items = (1...5).map { "\($0). Не используй сложные термины без объяснения." }
        let prompt = "Задача: объясни замыкания в Swift новичку.\n" + items.joined(separator: "\n")
        let cleaned = PromptQuality.removingDefects(from: prompt, systemPrompt: "", idea: "объясни замыкания")
        XCTAssertEqual(cleaned, "Задача: объясни замыкания в Swift новичку.\n1. Не используй сложные термины без объяснения.")
    }
}
