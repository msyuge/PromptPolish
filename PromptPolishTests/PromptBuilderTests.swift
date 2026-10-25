import XCTest
@testable import PromptPolish

final class PromptBuilderTests: XCTestCase {
    func testBundledSystemPromptIsLoaded() throws {
        let builder = try PromptBuilder.bundled()

        XCTAssertFalse(builder.systemPrompt.isEmpty)
        XCTAssertTrue(builder.systemPrompt.contains("<prompt>"))
        XCTAssertTrue(builder.systemPrompt.contains("never answer the prompt"))
    }

    func testMessagesAreSystemThenWrappedUserPrompt() {
        let builder = PromptBuilder(systemPrompt: "SYSTEM")

        let messages = builder.messages(for: "  напиши пост про кофе\n")

        XCTAssertEqual(messages, [
            ChatTurn(role: .system, content: "SYSTEM"),
            ChatTurn(role: .user, content: "Language: Russian\n<prompt>\nнапиши пост про кофе\n</prompt>\nWrite the result in Russian."),
        ])
    }

    func testUserPromptIsKeptVerbatimInside() {
        let prompt = "Сравни `let x = 1` и `var y = 2`\nссылка: https://example.com/a?b=c\n\n— 42%"
        let builder = PromptBuilder(systemPrompt: "SYSTEM")

        let user = builder.messages(for: prompt)[1].content

        XCTAssertTrue(user.contains("<prompt>\n\(prompt)\n</prompt>"))
    }

    func testEveryChatHasBundledStyle() throws {
        let builder = try PromptBuilder.bundled()

        for target in ChatTarget.allCases where target != .generic {
            XCTAssertFalse(builder.chatStyles[target.rawValue, default: ""].isEmpty, "Нет подсказки для \(target)")
        }
        XCTAssertTrue(builder.systemPrompt.contains("\"Style\""))
    }

    func testTargetAddsChatStyleBeforePrompt() {
        let builder = PromptBuilder(systemPrompt: "SYSTEM", chatStyles: ["claude": "Use XML tags."])

        let user = builder.messages(for: "напиши пост про кофе", target: .claude)[1].content

        XCTAssertEqual(
            user,
            "Target: Claude\nStyle: Use XML tags.\nLanguage: Russian\n<prompt>\nнапиши пост про кофе\n</prompt>\nWrite the result in Russian."
        )
    }

    func testGenericTargetHasNoStyleLines() {
        let builder = PromptBuilder(systemPrompt: "SYSTEM", chatStyles: ["claude": "Use XML tags."])

        let user = builder.messages(for: "fix my sql", target: .generic)[1].content

        XCTAssertFalse(user.contains("Target:"))
        XCTAssertFalse(user.contains("Style:"))
    }

    func testLanguageIsNamedExplicitly() {
        XCTAssertEqual(PromptBuilder.languageName(of: "объясни что такое замыкания в swift"), "Russian")
        XCTAssertEqual(PromptBuilder.languageName(of: "summarize this article for my boss"), "English")
        XCTAssertEqual(PromptBuilder.languageName(of: "напиши пост про кофе"), "Russian")
        XCTAssertEqual(PromptBuilder.languageName(of: "привет"), "Russian")
        XCTAssertEqual(PromptBuilder.languageName(of: "зроби мені план на тиждень"), "Ukrainian")
        XCTAssertEqual(PromptBuilder.languageName(of: "fix my sql its slow"), "English")
        XCTAssertEqual(PromptBuilder.languageName(of: "erkläre mir bitte, wie Closures in Swift funktionieren"), "German")
    }
}

final class ModelOutputCleanerTests: XCTestCase {
    func testPlainTextIsOnlyTrimmed() {
        XCTAssertEqual(ModelOutputCleaner.clean("  Напиши пост.\n"), "Напиши пост.")
    }

    func testRemovesPromptTags() {
        XCTAssertEqual(ModelOutputCleaner.clean("<prompt>\nНапиши пост.\n</prompt>"), "Напиши пост.")
    }

    func testRemovesLabel() {
        XCTAssertEqual(ModelOutputCleaner.clean("Улучшенный промт: Напиши пост."), "Напиши пост.")
        XCTAssertEqual(ModelOutputCleaner.clean("Improved prompt:\nWrite a post."), "Write a post.")
    }

    func testRemovesSurroundingQuotes() {
        XCTAssertEqual(ModelOutputCleaner.clean("«Напиши пост.»"), "Напиши пост.")
        XCTAssertEqual(ModelOutputCleaner.clean("\"Write a post.\""), "Write a post.")
    }

    func testKeepsQuotesThatAreNotWrapping() {
        let text = "«Война и мир» — перескажи кратко «Анну Каренину»"
        XCTAssertEqual(ModelOutputCleaner.clean(text), text)
    }

    func testRemovesCodeFence() {
        XCTAssertEqual(ModelOutputCleaner.clean("```text\nНапиши пост.\n```"), "Напиши пост.")
        XCTAssertEqual(ModelOutputCleaner.clean("```\nНапиши пост.\n```"), "Напиши пост.")
    }

    func testKeepsCodeInsidePrompt() {
        let text = "Объясни код:\n```swift\nlet x = 1\n```"
        XCTAssertEqual(ModelOutputCleaner.clean(text), text)
    }

    func testRemovesPlaceholderLinesAndBullets() {
        let raw = """
        Задача: напиши пост про кофе.
        Требования:
        - аудитория: [укажи аудиторию];
        - объём 800–1000 знаков.
        [вставь текст статьи]
        """
        XCTAssertEqual(ModelOutputCleaner.clean(raw), "Задача: напиши пост про кофе.\nТребования:\n- объём 800–1000 знаков.")
    }

    func testRemovesInlinePlaceholderInSentence() {
        XCTAssertEqual(
            ModelOutputCleaner.clean("Context: I am applying for a job at [company name]."),
            "Context: I am applying for a job at."
        )
    }

    func testKeepsCodeLikeBrackets() {
        let text = "Задача: объясни, почему `array[index]` падает.\nТребования:\n- сравни с [String: Int] и [1, 2];\n- учти Dictionary[Key]."
        XCTAssertEqual(ModelOutputCleaner.clean(text), text)
    }

    func testKeepsBracketsInsideCodeFence() {
        let text = "Задача: найди ошибку.\n```swift\nlet x = items [index]\nlet y = [first item]\n```"
        XCTAssertEqual(ModelOutputCleaner.clean(text), text)
    }

    func testRussianPromptGetsRussianSectionNames() {
        let raw = """
        Role: эксперт по Swift.

        Задача:объясни замыкания.
        Requirements:
        -используй примеры;
        •  будь краток.
        Answer format: определение, пример, итог.
        """
        XCTAssertEqual(
            ModelOutputCleaner.clean(raw, languageCode: "ru"),
            "Роль: эксперт по Swift.\nЗадача: объясни замыкания.\nТребования:\n- используй примеры;\n- будь краток.\nФормат ответа: определение, пример, итог."
        )
    }

    func testEnglishPromptKeepsEnglishSectionNames() {
        let raw = "Context: I study Swift.\n\nTask: explain closures.\nRequirements:\n- short"
        XCTAssertEqual(
            ModelOutputCleaner.clean(raw, languageCode: "en"),
            "Context: I study Swift.\nTask: explain closures.\nRequirements:\n- short"
        )
    }

    func testOrdinaryColonLinesAreUntouched() {
        let text = "Задача: сравни подходы.\nВажно: не используй сторонние библиотеки."
        XCTAssertEqual(ModelOutputCleaner.clean(text, languageCode: "ru"), text)
    }
}
