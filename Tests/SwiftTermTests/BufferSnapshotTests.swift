#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

/// `TerminalView.bufferSnapshot(rows:)` and `TerminalView.holdsPosition` — the copied buffer
/// read and the follow-output switch the Holidu IDE uses in place of reaching into `Terminal`.
@MainActor
final class BufferSnapshotTests {
    private func makeView(cols: Int = 10, rows: Int = 4, scrollback: Int = 100) -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160),
                                options: TerminalOptions(cols: cols, rows: rows, scrollback: scrollback))
        view.resize(cols: cols, rows: rows)
        return view
    }

    private func text(_ lines: [BufferLine]) -> [String] {
        lines.map { $0.translateToString(trimRight: true) }
    }

    @Test func noneCopiesOnlyTheAnchors() {
        let view = makeView()
        view.feed(text: (1...6).map { "l\($0)" }.joined(separator: "\r\n"))
        let snapshot = view.bufferSnapshot()
        #expect(snapshot.lines.isEmpty)
        #expect(snapshot.lineCount == 6)
        #expect(snapshot.yBase == 2)
        #expect(snapshot.yDisp == 2)
        #expect(snapshot.isAtBottom)
        #expect(snapshot.dimensions == TerminalDimensions(cols: 10, rows: 4))
        #expect(snapshot.cursor == Position(col: 2, row: 3))
        #expect(snapshot.scrollback == 100)
    }

    @Test func screenAndViewportDifferWhileScrolledBack() {
        let view = makeView()
        view.feed(text: (1...8).map { "l\($0)" }.joined(separator: "\r\n"))
        view.scrollTo(row: 1)

        let screen = view.bufferSnapshot(rows: .screen)
        #expect(text(screen.lines) == ["l5", "l6", "l7", "l8"])
        #expect(screen.firstRow == screen.yBase)
        #expect(!screen.isAtBottom)

        let viewport = view.bufferSnapshot(rows: .viewport)
        #expect(text(viewport.lines) == ["l2", "l3", "l4", "l5"])
        #expect(viewport.firstRow == 1)
    }

    @Test func tailIsClampedToTheBuffer() {
        let view = makeView()
        view.feed(text: (1...6).map { "l\($0)" }.joined(separator: "\r\n"))
        #expect(text(view.bufferSnapshot(rows: .tail(2)).lines) == ["l5", "l6"])
        #expect(view.bufferSnapshot(rows: .tail(1_000)).lines.count == 6)
        #expect(view.bufferSnapshot(rows: .tail(0)).lines.isEmpty)
    }

    /// The copies are the snapshot's own: later output must not rewrite them.
    @Test func copiedLinesDoNotChangeWithLaterOutput() {
        let view = makeView()
        view.feed(text: "before")
        let snapshot = view.bufferSnapshot(rows: .screen)
        view.feed(text: "\r\u{1b}[2Kafter")
        #expect(text(snapshot.lines).first == "before")
        #expect(text(view.bufferSnapshot(rows: .screen).lines).first == "after")
    }

    @Test func holdingPositionAtTheBottomStopsFollowingOutput() {
        let view = makeView()
        view.feed(text: (1...6).map { "l\($0)" }.joined(separator: "\r\n"))
        #expect(view.bufferSnapshot().isAtBottom)

        view.holdsPosition = true
        view.feed(text: "\r\nl7\r\nl8")
        let held = view.bufferSnapshot(rows: .viewport)
        #expect(!held.isAtBottom, "new output must not move a held viewport")
        #expect(text(held.lines) == ["l3", "l4", "l5", "l6"])

        view.holdsPosition = false
        view.scroll(toPosition: 1.0)
        view.feed(text: "\r\nl9")
        #expect(view.bufferSnapshot().isAtBottom, "released, the view follows output again")
    }
}
#endif
