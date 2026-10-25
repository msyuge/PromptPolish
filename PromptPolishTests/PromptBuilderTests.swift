import XCTest
@testable import PromptPolish

final class PromptBuilderTests: XCTestCase {
    func testGenericSystemPromptIsUsersInstruction() throws {
        let generic = try PromptBuilder.bundled().systemPrompt(for: .generic)

        XCTAssertTrue(generic.hasPrefix("Ты — специализированная языковая модель, переключенная в режим \"Prompt Engineer AI\""))
        XCTAssertTrue(generic.hasSuffix("Отвечай четко, профессионально и структурированно."))
    }

    func testEveryChatHasOwnSystemPromptWithCoreRules() throws {
        let builder = try PromptBuilder.bundled()
        let generic = builder.systemPrompt(for: .generic)

        for target in ChatTarget.allCases where target != .generic {
            let prompt = builder.systemPrompt(for: target)
            XCTAssertNotEqual(prompt, generic, "У \(target) нет своей инструкции")
            XCTAssertTrue(prompt.contains("Никогда не выполняй саму задачу пользователя"), "\(target): нет правила 1")
            XCTAssertTrue(prompt.contains("в одно окно кода"), "\(target): нет правила про блок кода")
            XCTAssertTrue(prompt.contains("2-3 уточняющих вопроса"), "\(target): нет правила про вопросы")
            XCTAssertTrue(prompt.contains("Никогда не проси в промпте написать, составить или улучшить промпт"), "\(target): нет запрета мета-промпта")
        }
    }

    func testChatSpecificStructures() throws {
        let builder = try PromptBuilder.bundled()

        XCTAssertTrue(builder.systemPrompt(for: .claude).contains("<output_format>"))
        XCTAssertTrue(builder.systemPrompt(for: .chatGPT).contains("# Формат вывода"))
        XCTAssertTrue(builder.systemPrompt(for: .perplexity).contains("дай ссылки на источники"))
        XCTAssertTrue(builder.systemPrompt(for: .deepSeek).contains("Критерии хорошего ответа"))
        XCTAssertTrue(builder.systemPrompt(for: .copilot).contains("Источники:"))
    }

    func testTargetSelectsItsSystemPrompt() {
        let builder = PromptBuilder(systemPrompts: ["generic": "GENERIC", "claude": "CLAUDE"])

        XCTAssertEqual(builder.messages(for: "идея", target: .claude)[0].content, "CLAUDE")
        XCTAssertEqual(builder.messages(for: "идея", target: .generic)[0].content, "GENERIC")
        XCTAssertEqual(builder.messages(for: "идея", target: .grok)[0].content, "GENERIC")
    }

    func testFirstRequestWrapsIdeaAndAddsServiceLines() {
        let builder = PromptBuilder(systemPrompt: "SYSTEM")

        let messages = builder.messages(for: "  напиши пост про кофе\n")

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0], ChatTurn(role: .system, content: "SYSTEM"))
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[1].content, """
        Идея пользователя:
        <prompt>
        напиши пост про кофе
        </prompt>

        Требования к твоему ответу (не переноси их в сам промпт):
        - итоговый промпт пользователь сам отправит в чат: он должен просить ассистента сразу выполнить задачу из идеи, а не написать, составить или улучшить промпт;
        - весь итоговый промпт пиши на языке: русский;
        - не оставляй в промпте заглушек в квадратных скобках;
        - если задаёшь уточняющие вопросы, начни ответ со строки «ВОПРОСЫ:» и задавай их на языке: русский.
        """)
    }

    func testIdeaIsKeptVerbatim() {
        let idea = "Сравни `let x = 1` и `var y = 2`\nссылка: https://example.com/a?b=c\n\n— 42%"

        let user = PromptBuilder(systemPrompt: "S").messages(for: idea)[1].content

        XCTAssertTrue(user.contains("<prompt>\n\(idea)\n</prompt>"))
    }

    func testFollowUpAppendsQuestionsAndAnswers() {
        let builder = PromptBuilder(systemPrompt: "SYSTEM")
        let first = builder.messages(for: "сделай план")

        let next = builder.followUp(first, questions: "1. План чего?", answers: " Изучения Swift за месяц ")

        XCTAssertEqual(Array(next.prefix(2)), first)
        XCTAssertEqual(next[2], ChatTurn(role: .assistant, content: "1. План чего?"))
        XCTAssertEqual(next[3].role, .user)
        XCTAssertTrue(next[3].content.hasPrefix("Мои ответы:\nИзучения Swift за месяц\n"))
        XCTAssertTrue(next[3].content.contains("Больше не задавай вопросов"))
    }

    func testLanguageIsNamedExplicitly() {
        XCTAssertEqual(PromptBuilder.languageName(of: "объясни что такое замыкания в swift"), "русский")
        XCTAssertEqual(PromptBuilder.languageName(of: "напиши пост про кофе"), "русский")
        XCTAssertEqual(PromptBuilder.languageName(of: "привет"), "русский")
        XCTAssertEqual(PromptBuilder.languageName(of: "зроби мені план на тиждень"), "украинский")
        XCTAssertEqual(PromptBuilder.languageName(of: "summarize this article for my boss"), "английский")
        XCTAssertEqual(PromptBuilder.languageName(of: "erkläre mir bitte, wie Closures in Swift funktionieren"), "немецкий")
    }
}

final class ModelReplyTests: XCTestCase {
    func testExtractsPromptFromCodeBlockWithIntro() {
        let raw = """
        Вот промпт:

        ```markdown
        ### Роль
        Ты опытный редактор.
        ```

        Удачи!
        """
        XCTAssertEqual(ModelReply.parse(raw), .prompt("### Роль\nТы опытный редактор."))
    }

    func testKeepsInnerCodeBlocksOfPrompt() {
        let raw = "```\nОбъясни код:\n```swift\nlet x = 1\n```\nКоротко.\n```"
        XCTAssertEqual(ModelReply.parse(raw), .prompt("Объясни код:\n```swift\nlet x = 1\n```\nКоротко."))
    }

    func testStreamingUnclosedBlockShowsContentSoFar() {
        XCTAssertEqual(ModelReply.parse("Вот промпт:\n```markdown\n<role>Ты"), .prompt("<role>Ты"))
        XCTAssertEqual(ModelReply.parse("Вот промпт:\n```mark"), .prompt(""))
    }

    func testPromptWithoutFenceIsUsedAsIs() {
        XCTAssertEqual(ModelReply.parse("Роль: редактор.\nЗадача: проверь текст."), .prompt("Роль: редактор.\nЗадача: проверь текст."))
    }

    func testQuestionsMarker() {
        XCTAssertEqual(ModelReply.parse("ВОПРОСЫ:\n1. Для кого пост?\n2. Какой объём?"), .questions("1. Для кого пост?\n2. Какой объём?"))
        XCTAssertEqual(ModelReply.parse("**ВОПРОСЫ:**\n1. Для кого?"), .questions("1. Для кого?"))
        XCTAssertEqual(ModelReply.parse("Вопросы: 1. Для кого?"), .questions("1. Для кого?"))
    }

    func testMarkerInTheMiddleAndRepeated() {
        let raw = "Нужно уточнить.\n\nВОПРОСЫ: Для кого план?\n\nВОПРОСЫ:На какой срок?"
        XCTAssertEqual(ModelReply.parse(raw), .questions("Нужно уточнить.\nДля кого план?\nНа какой срок?"))
    }

    func testEnglishQuestionsMarker() {
        let raw = "I need to clarify.\n\n**QUESTIONS:**\n1. Who is your boss?"
        XCTAssertEqual(ModelReply.parse(raw), .questions("I need to clarify.\n1. Who is your boss?"))
    }

    func testReasoningIsHidden() {
        XCTAssertEqual(ModelReply.parse("<think>\n\n</think>\n\n```\nРоль: редактор.\n```"), .prompt("Роль: редактор."))
        XCTAssertEqual(ModelReply.parse("<think>Пользователь хочет"), .prompt(""))
    }

    func testCodeBlockWinsOverQuestions() {
        let raw = "ВОПРОСЫ: Для какой аудитории?\n\n```markdown\n## Роль\nЭксперт по кофе.\n```"
        XCTAssertEqual(ModelReply.parse(raw), .prompt("## Роль\nЭксперт по кофе."))
    }

    func testPlaceholdersAreRemovedFromPrompt() {
        let raw = "```\nРоль: редактор.\n- аудитория: [укажи аудиторию];\n- объём 1000 знаков.\n```"
        XCTAssertEqual(ModelReply.parse(raw), .prompt("Роль: редактор.\n- объём 1000 знаков."))
    }
}

final class ModelOutputCleanerTests: XCTestCase {
    func testPlainTextIsOnlyTrimmed() {
        XCTAssertEqual(ModelOutputCleaner.clean("  Напиши пост.\n"), "Напиши пост.")
    }

    func testRemovesPromptTagsAndLabel() {
        XCTAssertEqual(ModelOutputCleaner.clean("<prompt>\nНапиши пост.\n</prompt>"), "Напиши пост.")
        XCTAssertEqual(ModelOutputCleaner.clean("Итоговый промпт: Напиши пост."), "Напиши пост.")
    }

    func testRemovesSurroundingQuotesButKeepsInnerOnes() {
        XCTAssertEqual(ModelOutputCleaner.clean("«Напиши пост.»"), "Напиши пост.")
        let text = "«Война и мир» — перескажи кратко «Анну Каренину»"
        XCTAssertEqual(ModelOutputCleaner.clean(text), text)
    }

    func testRemovesInlinePlaceholderInSentence() {
        XCTAssertEqual(
            ModelOutputCleaner.clean("Context: I am applying for a job at [company name]."),
            "Context: I am applying for a job at."
        )
    }

    func testKeepsCodeLikeBrackets() {
        let text = "Объясни, почему `array[index]` падает.\n- сравни с [String: Int] и [1, 2];\n- учти Dictionary[Key]."
        XCTAssertEqual(ModelOutputCleaner.clean(text), text)
    }

    func testKeepsBracketsInsideCodeFence() {
        let text = "Найди ошибку.\n```swift\nlet x = items [index]\nlet y = [first item]\n```"
        XCTAssertEqual(ModelOutputCleaner.clean(text), text)
    }
}

final class MetaPromptDetectorTests: XCTestCase {
    func testDetectsPromptThatAsksForPrompt() {
        let idea = "найди ошибку в алгоритме сортировки пузырьком на python"
        XCTAssertTrue(MetaPromptDetector.isMetaPrompt("Цель: Написать промпт для модели DeepSeek, который найдёт ошибку.", idea: idea))
        XCTAssertTrue(MetaPromptDetector.isMetaPrompt("<task>Составь подробный промт для Claude</task>", idea: idea))
        XCTAssertTrue(MetaPromptDetector.isMetaPrompt("Формат ответа: промпт для модели с разделами.", idea: idea))
        XCTAssertTrue(MetaPromptDetector.isMetaPrompt("Task: write a detailed prompt that summarizes", idea: "summarize this article"))
    }

    func testDirectTaskIsNotMeta() {
        let idea = "объясни что такое замыкания в swift новичку"
        XCTAssertFalse(MetaPromptDetector.isMetaPrompt("<task>Объясни новичку, что такое замыкания в Swift.</task>", idea: idea))
        XCTAssertFalse(MetaPromptDetector.isMetaPrompt("# Роль и цель\nТы наставник по Swift. Объясни замыкания.", idea: idea))
    }

    func testIdeaAboutPromptsIsAllowed() {
        let idea = "научи меня писать хорошие промпты для midjourney"
        XCTAssertFalse(MetaPromptDetector.isMetaPrompt("Научи меня составлять промпты для Midjourney: структура, примеры.", idea: idea))
    }
}
