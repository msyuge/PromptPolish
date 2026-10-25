import XCTest
@testable import PromptPolish

/// Реальная генерация на модели. Запускается только через `make integration`:
/// при первом запуске скачивает веса (≈1,7 ГБ), дальше работает офлайн.
final class LLMIntegrationTests: XCTestCase {
    private static let samples = [
        "напиши пост про кофе",
        "объясни что такое замыкания в swift",
        "summarize this article for my boss",
    ]

    func testGeneratesImprovedPrompts() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PROMPTPOLISH_INTEGRATION"] == "1",
            "Интеграционный тест: запустите make integration"
        )
        let engine = LLMEngine(builder: try PromptBuilder.bundled())

        let loadStart = ContinuousClock.now
        try await engine.prepare()
        var report = "Модель: \(engine.spec.id)\nЗагрузка: \(ContinuousClock.now - loadStart)\n"

        for prompt in Self.samples {
            let start = ContinuousClock.now
            var raw = ""
            var chunks = 0
            for try await chunk in engine.improve(prompt) {
                raw += chunk
                chunks += 1
            }
            let cleaned = ModelOutputCleaner.clean(raw)
            report += "\n=== \(prompt)\n\(cleaned)\n--- чанков: \(chunks), время: \(ContinuousClock.now - start)\n"

            XCTAssertGreaterThan(chunks, 1, "Ожидался стриминг несколькими кусками")
            XCTAssertFalse(cleaned.isEmpty)
            XCTAssertFalse(cleaned.contains("<prompt>"))
        }

        let output = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/integration-output.txt")
        try report.write(to: output, atomically: true, encoding: .utf8)
        print(report)
    }

    func testCancellationStopsGeneration() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PROMPTPOLISH_INTEGRATION"] == "1")
        let engine = LLMEngine(builder: try PromptBuilder.bundled())
        try await engine.prepare()

        var chunks = 0
        for try await _ in engine.improve("напиши подробный план изучения swift на год") {
            chunks += 1
            if chunks == 3 { break }
        }
        XCTAssertEqual(chunks, 3)
    }
}
