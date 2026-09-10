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

    @Test("dictation is centered above the whole input field without covering it")
    func aboveInputField() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 400)
        let input = CGRect(x: 120, y: 100, width: 300, height: 80)
        let pill = TextCaretIndicatorPlacement.frame(
            above: input,
            size: CGSize(width: 76, height: 22),
            visibleFrames: [visible],
            fallback: visible
        )

        #expect(pill.midX == input.midX)
        #expect(pill.minY == input.maxY + 8)
        #expect(!pill.intersects(input))
    }

    @Test("a field at the top uses the space below it and stays within the display")
    func topEdgeFallback() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 400)
        let input = CGRect(x: 465, y: 350, width: 30, height: 45)
        let pill = TextCaretIndicatorPlacement.frame(
            above: input,
            size: CGSize(width: 180, height: 36),
            visibleFrames: [visible],
            fallback: visible
        )

        #expect(pill.maxY == input.minY - 8)
        #expect(pill.maxX == visible.maxX)
        #expect(visible.contains(pill))
        #expect(!pill.intersects(input))
    }

    @Test("dictation remains on the input field's display including negative coordinates")
    func secondaryDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: -1280, y: 300, width: 1280, height: 1024)
        let input = CGRect(x: -1100, y: 700, width: 600, height: 90)
        let pill = TextCaretIndicatorPlacement.frame(
            above: input,
            size: CGSize(width: 76, height: 22),
            visibleFrames: [primary, secondary],
            fallback: primary
        )

        #expect(pill.midX == input.midX)
        #expect(pill.minY == input.maxY + 8)
        #expect(secondary.contains(pill))
    }

    @Test("a full-screen editable area keeps the dictation pill visible")
    func fullScreenInput() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 400)
        let pill = TextCaretIndicatorPlacement.frame(
            above: visible,
            size: CGSize(width: 76, height: 22),
            visibleFrames: [visible],
            fallback: visible
        )

        #expect(visible.contains(pill))
        #expect(pill.maxY == visible.maxY)
    }
}
