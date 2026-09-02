import AppKit
import Testing
@testable import MuesliNativeApp

@Suite("Text-caret indicator placement")
struct TextCaretIndicatorPlacementTests {
    @Test("Accessibility top-left coordinates convert to AppKit coordinates")
    func coordinateConversion() {
        let converted = TextCaretIndicatorPlacement.appKitRect(
            fromAccessibility: CGRect(x: 100, y: 200, width: 2, height: 20),
            primaryScreenTop: 900
        )

        #expect(converted == CGRect(x: 100, y: 680, width: 2, height: 20))
    }

    @Test("indicator sits beside the caret and flips left near the screen edge")
    func edgeAwarePlacement() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 400)
        let size = CGSize(width: 76, height: 22)
        let normal = TextCaretIndicatorPlacement.frame(
            beside: CGRect(x: 120, y: 180, width: 2, height: 20),
            size: size,
            visibleFrames: [visible],
            fallback: visible
        )
        let rightEdge = TextCaretIndicatorPlacement.frame(
            beside: CGRect(x: 490, y: 180, width: 2, height: 20),
            size: size,
            visibleFrames: [visible],
            fallback: visible
        )

        #expect(normal.minX == 130)
        #expect(normal.midY == 190)
        #expect(rightEdge.maxX == 482)
        #expect(rightEdge.minX < 490)
    }
}
