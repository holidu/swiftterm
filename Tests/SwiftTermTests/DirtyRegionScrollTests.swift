import Testing
@testable import SwiftTerm

/// Regression tests for dirty-region coordinate handling while the user has
/// scrolled up (`Terminal.userScrolling == true`).
///
/// An active-area row `y` corresponds to absolute buffer line `yBase + y` and to
/// viewport row `(yBase + y) - yDisp`. The two coordinate systems coincide only
/// when the viewport is pinned to the bottom (`yDisp == yBase`). When output
/// arrives while the user is scrolled up, the dirty tracking and the
/// active-to-viewport conversion must account for the `yBase - yDisp` offset,
/// otherwise freshly written rows are invalidated at the wrong position and the
/// screen is not repainted until a full redraw is forced.
final class DirtyRegionScrollTests {
    @Test func scrollInvariantRangeTracksAbsoluteLineWhenScrolledUp() throws {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 5, rows: 2, scrollback: 10)
        terminal.feed(text: "1\r\n2\r\n3\r\n4\r\n")

        #expect(terminal.buffer.yBase == 3)
        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)

        terminal.userScrolling = true
        terminal.setViewYDisp(0)
        terminal.clearUpdateRange()

        terminal.feed(text: "X")

        let cursorAbsoluteLine = terminal.buffer.yBase + terminal.buffer.y
        let range = try #require(terminal.getScrollInvariantUpdateRange())
        #expect(range.startY <= cursorAbsoluteLine)
        #expect(cursorAbsoluteLine <= range.endY)
    }

    @Test func visibleRowRangeIsIdentityWhenNotScrolled() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 5, rows: 4, scrollback: 10)
        for i in 1...6 { terminal.feed(text: "\(i)\r\n") }

        #expect(terminal.buffer.yDisp == terminal.buffer.yBase)

        let range = terminal.visibleRowRange(activeStart: 1, activeEnd: 2)
        #expect(range?.startY == 1)
        #expect(range?.endY == 2)
    }

    @Test func visibleRowRangeShiftsByScrollOffsetWhenScrolledUp() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 5, rows: 4, scrollback: 10)
        for i in 1...6 { terminal.feed(text: "\(i)\r\n") }

        let yBase = terminal.buffer.yBase
        #expect(yBase >= 2)

        terminal.userScrolling = true
        terminal.setViewYDisp(yBase - 1)

        let range = terminal.visibleRowRange(activeStart: 0, activeEnd: 1)
        #expect(range?.startY == 1)
        #expect(range?.endY == 2)
    }

    @Test func visibleRowRangeReturnsNilWhenChangedRowsScrolledOutOfView() {
        let (terminal, _) = TerminalTestHarness.makeTerminal(cols: 5, rows: 4, scrollback: 10)
        for i in 1...12 { terminal.feed(text: "\(i)\r\n") }

        let yBase = terminal.buffer.yBase
        #expect(yBase >= terminal.rows)

        terminal.userScrolling = true
        terminal.setViewYDisp(0)

        #expect(terminal.visibleRowRange(activeStart: 0, activeEnd: 0) == nil)
    }
}
