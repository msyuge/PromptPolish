import XCTest
@testable import PromptPolish

final class ChatTargetTests: XCTestCase {
    private func detect(_ url: String?, bundle: String? = "com.apple.Safari") -> ChatTarget {
        ChatTarget.detect(bundleID: bundle, pageURL: url.flatMap(URL.init(string:)))
    }

    func testDetectsChatsByHost() {
        XCTAssertEqual(detect("https://claude.ai/new"), .claude)
        XCTAssertEqual(detect("https://chatgpt.com/c/123"), .chatGPT)
        XCTAssertEqual(detect("https://chat.openai.com/"), .chatGPT)
        XCTAssertEqual(detect("https://gemini.google.com/app"), .gemini)
        XCTAssertEqual(detect("https://aistudio.google.com/prompts/new_chat"), .gemini)
        XCTAssertEqual(detect("https://www.perplexity.ai/search?q=x"), .perplexity)
        XCTAssertEqual(detect("https://chat.deepseek.com/"), .deepSeek)
        XCTAssertEqual(detect("https://grok.com/"), .grok)
        XCTAssertEqual(detect("https://copilot.microsoft.com/"), .copilot)
        XCTAssertEqual(detect("https://chat.mistral.ai/chat"), .mistral)
    }

    func testGrokInsideX() {
        XCTAssertEqual(detect("https://x.com/i/grok?conversation=1"), .grok)
        XCTAssertEqual(detect("https://x.com/home"), .generic)
    }

    func testHostMatchingIsNotSubstring() {
        XCTAssertEqual(detect("https://notclaude.ai/"), .generic)
        XCTAssertEqual(detect("https://claude.ai.example.com/"), .generic)
    }

    func testDesktopAppsByBundleID() {
        XCTAssertEqual(detect(nil, bundle: "com.anthropic.claudefordesktop"), .claude)
        XCTAssertEqual(detect(nil, bundle: "com.openai.chat"), .chatGPT)
        XCTAssertEqual(detect(nil, bundle: "ai.perplexity.mac"), .perplexity)
    }

    func testURLWinsOverBundleID() {
        XCTAssertEqual(detect("https://chatgpt.com/", bundle: "com.anthropic.claudefordesktop"), .chatGPT)
    }

    func testUnknownIsGeneric() {
        XCTAssertEqual(detect(nil, bundle: "com.apple.TextEdit"), .generic)
        XCTAssertEqual(detect("https://example.com/"), .generic)
        XCTAssertEqual(detect(nil, bundle: nil), .generic)
    }
}
