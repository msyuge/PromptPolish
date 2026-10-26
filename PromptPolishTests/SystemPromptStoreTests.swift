import XCTest
@testable import PromptPolish

@MainActor
final class SystemPromptStoreTests: XCTestCase {
    private var directory: URL!
    private let defaults: [SystemPromptStore.Key: String] = [
        .init(target: .generic, language: .ru): "GENERIC",
        .init(target: .claude, language: .ru): "CLAUDE",
        .init(target: .claude, language: .en): "CLAUDE-EN",
    ]

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "SystemPromptStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWithoutOverridesUsesDefaults() {
        let store = SystemPromptStore(defaults: defaults, directory: directory)

        XCTAssertEqual(store.text(for: .claude, language: .ru), "CLAUDE")
        XCTAssertFalse(store.isCustomized(.claude, language: .ru))
        XCTAssertEqual(store.builder.systemPrompt(for: .claude, language: .ru), "CLAUDE")
        XCTAssertEqual(store.builder.systemPrompt(for: .claude, language: .en), "CLAUDE-EN")
    }

    func testSaveWritesFileAndBuilderUsesIt() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)

        try store.save("  МОЯ ИНСТРУКЦИЯ\n", for: .claude, language: .ru)

        XCTAssertTrue(store.isCustomized(.claude, language: .ru))
        XCTAssertEqual(store.text(for: .claude, language: .ru), "МОЯ ИНСТРУКЦИЯ")
        XCTAssertEqual(store.builder.messages(for: "идея", target: .claude)[0].content, "МОЯ ИНСТРУКЦИЯ")
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "SystemPrompt-claude-ru.txt"), encoding: .utf8), "МОЯ ИНСТРУКЦИЯ")
        XCTAssertEqual(store.text(for: .generic, language: .ru), "GENERIC")
        XCTAssertEqual(store.text(for: .claude, language: .en), "CLAUDE-EN", "Правка русской инструкции не трогает английскую")
    }

    func testOverridesSurviveRestart() throws {
        try SystemPromptStore(defaults: defaults, directory: directory).save("ПРАВКА", for: .generic, language: .ru)

        let restarted = SystemPromptStore(defaults: defaults, directory: directory)

        XCTAssertEqual(restarted.text(for: .generic, language: .ru), "ПРАВКА")
    }

    func testResetRemovesOverride() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)
        try store.save("ПРАВКА", for: .claude, language: .ru)

        try store.reset(.claude, language: .ru)

        XCTAssertFalse(store.isCustomized(.claude, language: .ru))
        XCTAssertEqual(store.text(for: .claude, language: .ru), "CLAUDE")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: .claude, language: .ru).path(percentEncoded: false)))
    }

    func testSavingEmptyOrDefaultTextMeansNoOverride() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)
        try store.save("ПРАВКА", for: .claude, language: .ru)

        try store.save("   \n", for: .claude, language: .ru)
        XCTAssertFalse(store.isCustomized(.claude, language: .ru))

        try store.save("CLAUDE", for: .claude, language: .ru)
        XCTAssertFalse(store.isCustomized(.claude, language: .ru))
    }

    func testReloadPicksUpExternalEdits() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "ИЗ РЕДАКТОРА".write(to: store.fileURL(for: .claude, language: .ru), atomically: true, encoding: .utf8)

        store.reload()

        XCTAssertEqual(store.text(for: .claude, language: .ru), "ИЗ РЕДАКТОРА")
    }

    func testBundledStoreHasEveryChat() {
        let store = SystemPromptStore.bundled()

        for target in ChatTarget.allCases {
            for language in PromptLanguage.allCases {
                XCTAssertFalse(store.defaults[.init(target: target, language: language), default: ""].isEmpty, "Нет инструкции \(target)-\(language)")
            }
        }
    }
}
