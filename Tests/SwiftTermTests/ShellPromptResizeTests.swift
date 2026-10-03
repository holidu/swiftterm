#if os(macOS)
import Foundation
import XCTest

@testable import SwiftTerm

/// A zsh-style two-line prompt whose first row fills the width, redrawn after a width change by
/// moving up to the prompt's first row and clearing to the end of the screen.
final class ShellPromptResizeTests: XCTestCase {
    private let queue = DispatchQueue(label: "SwiftTerm.ShellPromptResizeTests")
    private let esc = "\u{1b}"

    private func terminal(cols: Int, clears: Bool) -> Terminal {
        let t = HeadlessTerminal(queue: queue,
                                 options: TerminalOptions(cols: cols, rows: 10, scrollback: 1_000)) { _ in }.terminal!
        t.clearsShellPromptOnResize = clears
        return t
    }

    private func drawPrompt(_ t: Terminal, cols: Int, osc133: Bool) {
        let header = "~/dir" + String(repeating: " ", count: cols - 13) + "12:00:00"
        precondition(header.count == cols)
        if osc133 { t.feed(text: "\(esc)]133;A\u{07}") }
        t.feed(text: "\r\(header)\r\n❯ ")
        if osc133 { t.feed(text: "\(esc)]133;B\u{07}") }
    }

    /// What zsh writes on SIGWINCH for a two-line prompt: up one row, clear below, draw again.
    private func redrawAfterResize(_ t: Terminal, cols: Int) {
        t.feed(text: "\(esc)[1A\r\(esc)[J")
        let header = "~/dir" + String(repeating: " ", count: cols - 13) + "12:00:00"
        t.feed(text: "\(header)\r\n❯ ")
    }

    private func text(_ t: Terminal) -> [String] {
        (0..<t.buffer.lines.count).map { t.buffer.lines[$0].translateToString(trimRight: true) }
    }

    private func promptHeaderRows(_ t: Terminal) -> Int {
        text(t).filter { $0.hasPrefix("~/dir") }.count
    }

    private func zoom(_ t: Terminal, osc133: Bool, widths: [Int]) {
        t.feed(text: "output-line\r\n")
        drawPrompt(t, cols: t.cols, osc133: osc133)
        for w in widths {
            t.resize(cols: w, rows: 10)
            redrawAfterResize(t, cols: w)
        }
    }

    func testPromptIsNotDuplicatedAcrossWidthChanges() {
        let t = terminal(cols: 40, clears: true)
        zoom(t, osc133: true, widths: [30, 40, 30, 40])
        XCTAssertEqual(promptHeaderRows(t), 1, text(t).joined(separator: "\n"))
        XCTAssertEqual(text(t).filter { $0 == "output-line" }.count, 1)
    }

    func testWithoutTheOptionReflowLeavesAStaleHeaderRow() {
        let t = terminal(cols: 40, clears: false)
        zoom(t, osc133: true, widths: [30, 40, 30, 40])
        XCTAssertGreaterThan(promptHeaderRows(t), 1)
    }

    func testWithoutOsc133NothingIsCleared() {
        let t = terminal(cols: 40, clears: true)
        zoom(t, osc133: false, widths: [30])
        XCTAssertGreaterThan(promptHeaderRows(t), 1)
    }

    func testOutputOfARunningCommandIsKept() {
        let t = terminal(cols: 40, clears: true)
        drawPrompt(t, cols: 40, osc133: true)
        t.feed(text: "ls\r\n\(esc)]133;C\u{07}running-output\r\n")
        t.resize(cols: 30, rows: 10)
        XCTAssertTrue(text(t).contains("running-output"))
        XCTAssertTrue(text(t).contains { $0.hasPrefix("~/dir") })
    }
}
#endif
