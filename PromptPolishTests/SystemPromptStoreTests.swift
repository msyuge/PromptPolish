import XCTest
@testable import PromptPolish

@MainActor
final class SystemPromptStoreTests: XCTestCase {
    private var directory: URL!
    private let defaults: [ChatTarget: String] = [.generic: "GENERIC", .claude: "CLAUDE"]

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "SystemPromptStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWithoutOverridesUsesDefaults() {
        let store = SystemPromptStore(defaults: defaults, directory: directory)

        XCTAssertEqual(store.text(for: .claude), "CLAUDE")
        XCTAssertFalse(store.isCustomized(.claude))
        XCTAssertEqual(store.builder.systemPrompt(for: .claude), "CLAUDE")
    }

    func testSaveWritesFileAndBuilderUsesIt() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)

        try store.save("  МОЯ ИНСТРУКЦИЯ\n", for: .claude)

        XCTAssertTrue(store.isCustomized(.claude))
        XCTAssertEqual(store.text(for: .claude), "МОЯ ИНСТРУКЦИЯ")
        XCTAssertEqual(store.builder.messages(for: "идея", target: .claude)[0].content, "МОЯ ИНСТРУКЦИЯ")
        XCTAssertEqual(try String(contentsOf: directory.appending(path: "SystemPrompt-claude.txt"), encoding: .utf8), "МОЯ ИНСТРУКЦИЯ")
        XCTAssertEqual(store.text(for: .generic), "GENERIC")
    }

    func testOverridesSurviveRestart() throws {
        try SystemPromptStore(defaults: defaults, directory: directory).save("ПРАВКА", for: .generic)

        let restarted = SystemPromptStore(defaults: defaults, directory: directory)

        XCTAssertEqual(restarted.text(for: .generic), "ПРАВКА")
    }

    func testResetRemovesOverride() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)
        try store.save("ПРАВКА", for: .claude)

        try store.reset(.claude)

        XCTAssertFalse(store.isCustomized(.claude))
        XCTAssertEqual(store.text(for: .claude), "CLAUDE")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: .claude).path(percentEncoded: false)))
    }

    func testSavingEmptyOrDefaultTextMeansNoOverride() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)
        try store.save("ПРАВКА", for: .claude)

        try store.save("   \n", for: .claude)
        XCTAssertFalse(store.isCustomized(.claude))

        try store.save("CLAUDE", for: .claude)
        XCTAssertFalse(store.isCustomized(.claude))
    }

    func testReloadPicksUpExternalEdits() throws {
        let store = SystemPromptStore(defaults: defaults, directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "ИЗ РЕДАКТОРА".write(to: store.fileURL(for: .claude), atomically: true, encoding: .utf8)

        store.reload()

        XCTAssertEqual(store.text(for: .claude), "ИЗ РЕДАКТОРА")
    }

    func testBundledStoreHasEveryChat() {
        let store = SystemPromptStore.bundled()

        for target in ChatTarget.allCases {
            XCTAssertFalse(store.defaults[target, default: ""].isEmpty, "Нет стандартной инструкции для \(target)")
        }
    }
}
