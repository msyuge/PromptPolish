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
    3. Claude лучше всего понимает разделы в XML-тегах. Собери промпт из таких разделов, в этом порядке.
    - <role> — конкретная экспертиза, нужная для этой задачи;
    - <context> — зачем нужна задача, для кого результат, что уже известно;
    - <output_format> — точная форма ответа: структура, длина, оформление.
    Последний пункт «дай ссылки на источники».
    """

    func testDetectsCopiedSectionDescriptions() {
        let prompt = """
        <role>Конкретная экспертиза, нужная для этой задачи.</role>
        <context>Зачем нужна задача, для кого результат, что уже известно.</context>
        <task>Добавь в утилиту меню «Системные инструкции».</task>
        """

        let echoed = PromptQuality.echoedFragments(in: prompt, systemPrompt: claudeSystemPrompt)

        XCTAssertTrue(echoed.contains("конкретная экспертиза, нужная для этой задачи"))
        XCTAssertTrue(echoed.contains("зачем нужна задача, для кого результат, что уже известно"))
        XCTAssertEqual(
            PromptQuality.issues(in: prompt, idea: "добавь меню", systemPrompt: claudeSystemPrompt),
            [.templateEcho(echoed)]
        )
    }

    func testFilledPromptIsClean() {
        let prompt = """
        <role>Senior macOS-разработчик, SwiftUI и AppKit.</role>
        <context>Утилита в строке меню улучшает промпты; нужен редактор инструкций.</context>
        <task>Добавь пункт меню «Системные инструкции» с окном редактирования.</task>
        """
        XCTAssertEqual(PromptQuality.issues(in: prompt, idea: "добавь меню инструкций", systemPrompt: claudeSystemPrompt), [])
    }

    func testQuotedPhrasesAreAllowed() {
        XCTAssertEqual(PromptQuality.echoedFragments(in: "Учти:\n- дай ссылки на источники.", systemPrompt: claudeSystemPrompt), [])
    }

    func testDetectsMetaTaskTogetherWithEcho() {
        let prompt = "<task>Написать промпт для ассистента, чтобы он добавил меню.</task>\n<role>Конкретная экспертиза, нужная для этой задачи.</role>"

        let issues = PromptQuality.issues(in: prompt, idea: "Добавить меню", systemPrompt: claudeSystemPrompt)

        XCTAssertEqual(issues.first, .metaTask)
        XCTAssertEqual(issues.count, 2)
    }

    func testRemovingEchoDropsCopiedLinesAndEmptyTags() {
        let prompt = """
        <role>Конкретная экспертиза, нужная для этой задачи.</role>
        <task>Добавь в утилиту меню «Системные инструкции».</task>
        <output_format>
        Точная форма ответа: структура, длина, оформление.
        </output_format>
        """

        let cleaned = PromptQuality.removingEcho(from: prompt, systemPrompt: claudeSystemPrompt)

        XCTAssertEqual(cleaned, "<task>Добавь в утилиту меню «Системные инструкции».</task>")
    }

    func testCorrectionMessageNamesTheProblems() {
        let builder = PromptBuilder(systemPrompt: "S")
        let history = builder.messages(for: "идея")

        let next = builder.correcting(history, reply: "ответ", issues: [.metaTask, .templateEcho(["зачем нужна задача, для кого результат"])])

        XCTAssertEqual(next[2], ChatTurn(role: .assistant, content: "ответ"))
        XCTAssertTrue(next[3].content.contains("просит написать промпт"))
        XCTAssertTrue(next[3].content.contains("«зачем нужна задача, для кого результат»"))
    }

    func testBundledChatPromptsHaveNoCopyableSkeleton() throws {
        let builder = try PromptBuilder.bundled()
        for target in ChatTarget.allCases where target != .generic {
            let prompt = builder.systemPrompt(for: target)
            XCTAssertFalse(prompt.contains("```\n<"), "\(target): каркас в блоке кода")
            XCTAssertFalse(prompt.contains("```\n#"), "\(target): каркас в блоке кода")
            XCTAssertTrue(prompt.contains("сами описания в промпт не переноси") || target == .perplexity, "\(target): нет запрета копировать описания")
        }
    }
}
