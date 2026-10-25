import XCTest
@testable import PromptPolish

final class PanelPlacementTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 480, height: 320)

    func testPlacesBelowAnchorAlignedToItsLeftEdge() {
        let anchor = CGRect(x: 300, y: 600, width: 200, height: 20)

        let frame = PanelPlacement.frame(size: size, anchor: anchor, visible: visible)

        XCTAssertEqual(frame.minX, 300)
        XCTAssertEqual(frame.maxY, 600 - PanelPlacement.gap)
    }

    func testPlacesAboveWhenNoRoomBelow() {
        let anchor = CGRect(x: 300, y: 100, width: 200, height: 20)

        let frame = PanelPlacement.frame(size: size, anchor: anchor, visible: visible)

        XCTAssertEqual(frame.minY, 120 + PanelPlacement.gap)
    }

    func testStaysInsideScreenHorizontally() {
        let anchor = CGRect(x: 1400, y: 600, width: 20, height: 20)

        let frame = PanelPlacement.frame(size: size, anchor: anchor, visible: visible)

        XCTAssertEqual(frame.maxX, visible.maxX - PanelPlacement.margin)
    }

    func testTallAnchorFallsBackToClampedPosition() {
        let anchor = CGRect(x: 100, y: 50, width: 800, height: 820)

        let frame = PanelPlacement.frame(size: size, anchor: anchor, visible: visible)

        XCTAssertTrue(visible.contains(frame))
    }

    func testWorksOnSecondaryScreenWithOffsetOrigin() {
        let secondary = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let anchor = CGRect(x: -1900, y: 900, width: 100, height: 20)

        let frame = PanelPlacement.frame(size: size, anchor: anchor, visible: secondary)

        XCTAssertTrue(secondary.contains(frame))
        XCTAssertEqual(frame.minX, -1900)
    }
}
