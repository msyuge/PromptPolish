import AppKit
import XCTest
@testable import PromptPolish

@MainActor
final class ClipboardTextTransferTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private var original: PasteboardSnapshot!

    override func setUp() async throws {
        pasteboard = .makeUnique()
        fillWithUserContent(pasteboard)
        original = PasteboardSnapshot.capture(from: pasteboard)
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private func assertClipboardRestored(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(PasteboardSnapshot.capture(from: pasteboard), original, file: file, line: line)
    }

    func testCopyReturnsSelectionAndRestoresClipboard() async throws {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "write me a poem please", selection: "a poem")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        let result = try await transfer.copySelection(selectAllIfEmpty: true)

        XCTAssertEqual(result.text, "a poem")
        XCTAssertFalse(result.selectedAll)
        XCTAssertEqual(field.sent, [.copy])
        assertClipboardRestored()
    }

    func testCopyWithoutSelectionSelectsAllField() async throws {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "whole prompt")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        let result = try await transfer.copySelection(selectAllIfEmpty: true)

        XCTAssertEqual(result.text, "whole prompt")
        XCTAssertTrue(result.selectedAll)
        XCTAssertEqual(field.sent, [.copy, .selectAll, .copy])
        assertClipboardRestored()
    }

    func testCopyDoesNotSelectAllWhenNotAllowed() async {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "whole prompt")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        await assertThrows(TextBridgeError.noText) {
            _ = try await transfer.copySelection(selectAllIfEmpty: false)
        }
        XCTAssertEqual(field.sent, [.copy])
        assertClipboardRestored()
    }

    func testCopyFromEmptyFieldThrowsAndRestoresClipboard() async {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        await assertThrows(TextBridgeError.noText) {
            _ = try await transfer.copySelection(selectAllIfEmpty: true)
        }
        assertClipboardRestored()
    }

    func testWhitespaceOnlySelectionCountsAsNoText() async {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "  \n", selection: "  \n")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        await assertThrows(TextBridgeError.noText) {
            _ = try await transfer.copySelection(selectAllIfEmpty: true)
        }
        assertClipboardRestored()
    }

    func testPasteDeliversTextAndRestoresClipboard() async throws {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "old", selection: "old")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        try await transfer.paste("improved prompt", selectAll: false)

        XCTAssertEqual(field.pasted, ["improved prompt"])
        XCTAssertEqual(field.sent, [.paste])
        assertClipboardRestored()
    }

    func testPasteWithSelectAllSendsSelectAllFirst() async throws {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "old")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        try await transfer.paste("new", selectAll: true)

        XCTAssertEqual(field.sent, [.selectAll, .paste])
        XCTAssertEqual(field.pasted, ["new"])
        assertClipboardRestored()
    }

    func testPasteMarksTemporaryContentAsTransient() async throws {
        let recorder = TransientRecorder(pasteboard: pasteboard)
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: recorder, timing: .fast)

        try await transfer.paste("new", selectAll: false)

        XCTAssertEqual(recorder.typesAtPaste, [.string, .transient])
        assertClipboardRestored()
    }

    func testPasteIntoEmptyClipboardLeavesItEmpty() async throws {
        pasteboard.clearContents()
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "old", selection: "old")
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: .fast)

        try await transfer.paste("new", selectAll: false)

        XCTAssertEqual(pasteboard.pasteboardItems?.count ?? 0, 0)
    }

    func testCancelledPasteStillRestoresClipboard() async throws {
        let field = FakeTextField(pasteboard: pasteboard, fieldText: "old", selection: "old")
        var timing = ClipboardTextTransfer.Timing.fast
        timing.pasteSettle = .seconds(10)
        let transfer = ClipboardTextTransfer(pasteboard: pasteboard, keys: field, timing: timing)

        let task = Task { try await transfer.paste("new", selectAll: false) }
        while field.pasted.isEmpty { await Task.yield() }
        task.cancel()
        let result = await task.result

        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError) }
        assertClipboardRestored()
    }

    private func assertThrows(
        _ expected: TextBridgeError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("Ожидалась ошибка \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? TextBridgeError, expected, file: file, line: line)
        }
    }
}

@MainActor
private final class TransientRecorder: KeySending {
    let pasteboard: NSPasteboard
    private(set) var typesAtPaste: [NSPasteboard.PasteboardType] = []

    init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
    }

    func send(_ shortcut: KeyShortcut) {
        if shortcut == .paste {
            typesAtPaste = pasteboard.pasteboardItems?.first?.types ?? []
        }
    }
}
