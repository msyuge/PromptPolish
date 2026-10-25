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
            ChatTurn(role: .user, content: "Language: Russian\n<prompt>\nнапиши пост про кофе\n</prompt>"),
        ])
    }

    func testUserPromptIsKeptVerbatimInside() {
        let prompt = "Сравни `let x = 1` и `var y = 2`\nссылка: https://example.com/a?b=c\n\n— 42%"
        let builder = PromptBuilder(systemPrompt: "SYSTEM")

        let user = builder.messages(for: prompt)[1].content

        XCTAssertTrue(user.hasSuffix("<prompt>\n\(prompt)\n</prompt>"))
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
}
