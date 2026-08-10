import Foundation
import Testing
@testable import SwiftTerm

#if os(macOS)
import AppKit

/// Damaged rows are recorded against `yBase` (`Terminal.updateRange` is fed `buffer.y`,
/// `scrollTop`, `scrollBottom`) but painted against `yDisp`. While the viewport is scrolled up
/// the two disagree by `yBase - yDisp`, so an in-place redraw — a TUI rewriting its input box
/// with no linefeed to trigger a full-screen repaint — invalidated rows the user was not looking
/// at, while the rows that actually changed kept their stale pixels.
final class ScrollDamageTests {
    private final class RecordingTerminalView: TerminalView {
        var invalidated: [NSRect] = []

        override func setNeedsDisplay(_ invalidRect: NSRect) {
            invalidated.append(invalidRect)
            super.setNeedsDisplay(invalidRect)
        }
    }

    /// A view with enough scrollback to scroll up in. 25 rows at this size.
    private func makeViewWithScrollback() -> RecordingTerminalView {
        let view = RecordingTerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        for i in 0..<120 {
            view.terminal.feed(text: "line \(i)\r\n")
        }
        return view
    }

    /// True when some invalidation rect covers the full height of `screenRow`, counted from the
    /// top of the *viewport* — which is what the user is actually looking at.
    private func covers(_ rects: [NSRect], screenRow: Int, in view: TerminalView) -> Bool {
        let cellHeight = view.cellDimension.height
        let top = view.frame.height - (CGFloat(screenRow) * cellHeight)
        let bottom = top - cellHeight
        // Half a pixel of slack at each edge for the sub-cell padding the renderer adds.
        return rects.contains { $0.minY <= bottom + 0.5 && $0.maxY >= top - 0.5 }
    }

    /// Rewrites row `atRow` (zero-based, relative to `yBase`) in place and returns what the view
    /// invalidated. The cursor is parked on the row and the update range cleared *before* the
    /// text is fed: cursor addressing dirties the row it leaves as well as the one it lands on,
    /// and a stray dirty row at the bottom of the screen makes the invalidation run to the
    /// bottom edge of the view, which hides the very bug under test.
    private func invalidationAfterInPlaceEdit(
        on view: RecordingTerminalView,
        atRow row: Int
    ) -> [NSRect] {
        let esc = "\u{1b}"
        view.terminal.feed(text: "\(esc)[\(row + 1);1H")
        view.terminal.clearUpdateRange()
        view.invalidated.removeAll()

        view.terminal.feed(text: "REWRITTEN")
        view.updateDisplay(notifyAccessibility: false)
        return view.invalidated
    }

    /// The regression. Scrolled up 3 rows, an in-place edit of a row that is still on screen has
    /// to invalidate where that row is actually drawn — 3 rows lower than where it was recorded.
    /// Before the fix the invalidated band was rows 9-10 while the edit landed on row 12, so the
    /// typed text never repainted and the caret advanced over stale blanks.
    @Test func testInPlaceEditWhileScrolledUpInvalidatesTheRowItActuallyDraws() {
        let view = makeViewWithScrollback()
        let scrollUpBy = 3
        let editedRow = 9

        view.scrollTo(row: view.terminal.buffer.yBase - scrollUpBy)
        #expect(view.terminal.buffer.yBase - view.terminal.buffer.yDisp == scrollUpBy)

        let rects = invalidationAfterInPlaceEdit(on: view, atRow: editedRow)

        // The edit must not have moved the viewport; that would heal it for the wrong reason.
        #expect(view.terminal.buffer.yBase - view.terminal.buffer.yDisp == scrollUpBy)
        #expect(!rects.isEmpty)
        #expect(covers(rects, screenRow: editedRow + scrollUpBy, in: view))
    }

    /// At the live bottom the shift is zero and the band is unchanged: the row is invalidated
    /// exactly where it was written.
    @Test func testInPlaceEditAtBottomInvalidatesTheEditedRow() {
        let view = makeViewWithScrollback()
        let editedRow = 9
        #expect(view.terminal.buffer.yBase == view.terminal.buffer.yDisp)

        let rects = invalidationAfterInPlaceEdit(on: view, atRow: editedRow)

        #expect(!rects.isEmpty)
        #expect(covers(rects, screenRow: editedRow, in: view))
    }

    /// The band may only ever grow. `updateFullScreen()` and `refresh(startRow:endRow:)` are
    /// called by the *view* in viewport coordinates, so translating the band down instead of
    /// extending it would clip its top rows away while scrolled up.
    @Test func testFullScreenInvalidationStillCoversTopRowWhileScrolledUp() {
        let view = makeViewWithScrollback()
        view.scrollTo(row: view.terminal.buffer.yBase - 4)

        view.invalidated.removeAll()
        view.terminal.updateFullScreen()
        view.updateDisplay(notifyAccessibility: false)

        #expect(covers(view.invalidated, screenRow: 0, in: view))
        #expect(covers(view.invalidated, screenRow: view.terminal.rows - 1, in: view))
    }
}
#endif
