import AppKit
import XCTest
@testable import PromptPolish

@MainActor
final class PasteboardSnapshotTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = .makeUnique()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    func testCapturesAllItemsAndTypesInOrder() {
        fillWithUserContent(pasteboard)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].map(\.type), [.string, .html, .custom])
        XCTAssertEqual(snapshot.items[0][2].data, Data([0x00, 0xFF, 0x10]))
        XCTAssertEqual(snapshot.items[1].map(\.type), [.URL])
    }

    func testRestoreBringsBackOriginalContentAfterOverwrite() {
        fillWithUserContent(pasteboard)
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("something else", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(PasteboardSnapshot.capture(from: pasteboard), snapshot)
        XCTAssertEqual(pasteboard.string(forType: .string), "user text")
        XCTAssertEqual(pasteboard.pasteboardItems?[1].string(forType: .URL), "https://example.com")
    }

    func testRestoringEmptySnapshotLeavesPasteboardEmpty() {
        pasteboard.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertTrue(snapshot.items.isEmpty)

        pasteboard.setString("temporary", forType: .string)
        snapshot.restore(to: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count ?? 0, 0)
    }
}
