import XCTest
@testable import PromptPolish

final class PromptBuilderTests: XCTestCase {
    func testLanguageSetIsChosenByScript() {
        XCTAssertEqual(PromptLanguage.of("напиши пост про кофе"), .ru)
        XCTAssertEqual(PromptLanguage.of("привет"), .ru)
        XCTAssertEqual(PromptLanguage.of("объясни closures в Swift"), .ru)
        XCTAssertEqual(PromptLanguage.of("explain swift closures"), .en)
        XCTAssertEqual(PromptLanguage.of("erkläre mir Closures"), .en)
        XCTAssertEqual(PromptLanguage.of("fix the bug in the function that parses the JSON from api, ошибка"), .en)
        XCTAssertEqual(PromptLanguage.of("сделай ревью pull request в репозитории"), .ru)
    }

    func testEveryChatHasBothLanguageSetsWithCoreRules() throws {
        let builder = try PromptBuilder.bundled()
        let rules: [PromptLanguage: [String]] = [
            .en: ["Never do the task yourself.", "to write, improve or generate a prompt", "one markdown code block",
                  "the request says that the idea needs clarification", "Never ask about what you can choose yourself", "Keep every fact from the idea exactly", "No placeholders in square brackets"],
            .ru: ["Никогда не выполняй задачу сам.", "написать, улучшить или сгенерировать промпт", "один markdown-блок кода",
                  "в запросе сказано, что идея требует уточнения", "Никогда не спрашивай о том, что можешь выбрать сам", "Сохраняй все факты из идеи дословно", "Никаких заглушек в квадратных скобках"],
        ]
        for language in PromptLanguage.allCases {
            let generic = builder.systemPrompt(for: .generic, language: language)
            for target in ChatTarget.allCases {
                let prompt = builder.systemPrompt(for: target, language: language)
                if target != .generic { XCTAssertNotEqual(prompt, generic, "\(target)-\(language): нет своей инструкции") }
                for rule in rules[language]! {
                    XCTAssertTrue(prompt.contains(rule), "\(target)-\(language): нет правила «\(rule)»")
                }
                XCTAssertTrue(prompt.contains(language.questionsMarker), "\(target)-\(language): нет маркера вопросов")
            }
        }
        let english = ChatTarget.allCases.map { builder.systemPrompt(for: $0, language: .en) }.joined()
        XCTAssertFalse(english.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }, "В английских инструкциях осталась кириллица")
    }

    func testChatSpecificStructures() throws {
        let builder = try PromptBuilder.bundled()
        let en = { builder.systemPrompt(for: $0, language: .en) }
        let ru = { builder.systemPrompt(for: $0, language: .ru) }

        XCTAssertTrue(en(.claude).contains("<output_format>") && ru(.claude).contains("<output_format>"))
        XCTAssertTrue(en(.chatGPT).contains("# Output format") && ru(.chatGPT).contains("# Формат вывода"))
        XCTAssertTrue(en(.gemini).contains("**Output format:**") && ru(.gemini).contains("**Формат ответа:**"))
        XCTAssertTrue(en(.perplexity).contains("Do not assign a role") && ru(.perplexity).contains("Не задавай роль"))
        XCTAssertTrue(en(.deepSeek).contains("Success criteria:") && ru(.deepSeek).contains("Критерии хорошего ответа:"))
        XCTAssertTrue(en(.grok).contains("posts on X") && ru(.grok).contains("посты в X"))
        XCTAssertTrue(en(.copilot).contains("Sources:") && ru(.copilot).contains("Источники:"))
        XCTAssertTrue(en(.mistral).contains("## Answer format") && ru(.mistral).contains("## Формат ответа"))
    }

    func testIdeaLanguagePicksInstructionSet() {
        let builder = PromptBuilder(systemPrompts: ["generic-ru": "RU", "generic-en": "EN", "claude-ru": "CLAUDE-RU", "claude-en": "CLAUDE-EN"])

        XCTAssertEqual(builder.messages(for: "идея", target: .claude)[0].content, "CLAUDE-RU")
        XCTAssertEqual(builder.messages(for: "an idea", target: .claude)[0].content, "CLAUDE-EN")
        XCTAssertEqual(builder.messages(for: "идея", target: .grok)[0].content, "RU")
        XCTAssertEqual(builder.messages(for: "an idea", target: .generic)[0].content, "EN")
    }

    func testRussianRequestIsInRussian() {
        let messages = PromptBuilder(systemPrompt: "SYSTEM").messages(for: "  напиши пост про кофе для телеграм-канала\n")

        XCTAssertEqual(messages[0], ChatTurn(role: .system, content: "SYSTEM"))
        XCTAssertEqual(messages[1].content, """
        Идея пользователя:
        <idea>
        напиши пост про кофе для телеграм-канала
        </idea>

        Требования к ответу (не переноси их в сам промпт):
        - пользователь вставит промпт в чат как есть: промпт должен просить ассистента сразу выполнить задачу из идеи, а не написать, улучшить или сгенерировать промпт;
        - никаких заглушек в квадратных скобках;
        - если задаёшь уточняющие вопросы, начни ответ со строки «ВОПРОСЫ:».

        Весь промпт (или вопросы) пиши на языке: русский.
        """)
    }

    func testEnglishRequestIsInEnglish() {
        let content = PromptBuilder(systemPrompt: "SYSTEM").messages(for: "explain swift closures")[1].content

        XCTAssertTrue(content.hasPrefix("User idea:\n<idea>\nexplain swift closures\n</idea>"))
        XCTAssertTrue(content.contains("start your reply with the line \"QUESTIONS:\""))
        XCTAssertTrue(content.hasSuffix("Write the entire prompt (or the questions) in English."))
    }

    func testIdeaIsKeptVerbatim() {
        let idea = "Сравни `let x = 1` и `var y = 2`\nссылка: https://example.com/a?b=c\n\n— 42%"

        let user = PromptBuilder(systemPrompt: "S").messages(for: idea)[1].content

        XCTAssertTrue(user.contains("<idea>\n\(idea)\n</idea>"))
    }

    func testFollowUpIsInIdeaLanguage() {
        let builder = PromptBuilder(systemPrompt: "SYSTEM")
        let ru = builder.followUp(builder.messages(for: "сделай план"), questions: "1. План чего?", answers: " Изучения Swift за месяц ")
        let en = builder.followUp(builder.messages(for: "make a plan"), questions: "1. A plan for what?", answers: "Learning Swift")

        XCTAssertEqual(ru[2], ChatTurn(role: .assistant, content: "1. План чего?"))
        XCTAssertTrue(ru[3].content.hasPrefix("Мои ответы:\nИзучения Swift за месяц\n"))
        XCTAssertTrue(ru[3].content.contains("Больше не задавай вопросов"))
        XCTAssertTrue(en[3].content.hasPrefix("My answers:\nLearning Swift\n"))
        XCTAssertTrue(en[3].content.contains("Do not ask more questions"))
    }

    func testLanguageIsNamedExplicitly() {
        XCTAssertEqual(PromptBuilder.languageName(of: "объясни что такое замыкания в swift", in: .ru), "русский")
        XCTAssertEqual(PromptBuilder.languageName(of: "напиши пост про кофе"), "Russian")
        XCTAssertEqual(PromptBuilder.languageName(of: "привет"), "Russian")
        XCTAssertEqual(PromptBuilder.languageName(of: "зроби мені план на тиждень"), "Ukrainian")
        XCTAssertEqual(PromptBuilder.languageName(of: "summarize this article for my boss"), "English")
        XCTAssertEqual(PromptBuilder.languageName(of: "erkläre mir bitte, wie Closures in Swift funktionieren"), "German")
        XCTAssertEqual(PromptBuilder.languageName(of: "сравни тарифы мобильных операторов"), "Russian")
        XCTAssertEqual(PromptBuilder.languageName(of: "сравни тарифы мобильных операторов в россии", in: .ru), "русский")
        XCTAssertEqual(PromptBuilder.languageCode(of: "напиши пост про кофе"), "ru")
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

    func testQuestionsInsideCodeBlockAfterMarker() {
        XCTAssertEqual(ModelReply.parse("ВОПРОСЫ:\n```\n1. Для кого?\n2. Какой объём?\n```"), .questions("1. Для кого?\n2. Какой объём?"))
        XCTAssertEqual(
            ModelReply.parse("ВОПРОСЫ:\n```\n1. Какой уровень знаний (новичок, средний)\n2. Нужен ли пример кода\n```"),
            .questions("1. Какой уровень знаний (новичок, средний)\n2. Нужен ли пример кода")
        )
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
