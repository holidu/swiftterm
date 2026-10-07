//
//  LocalProcessInputGateTests.swift
//
//  In SwiftTerm 2 user input goes from the input sender straight to the process, so a subclass
//  override of send(source:data:) never sees a keystroke. setProcessInputGate is how a host holds
//  input; these drive a real PTY through it.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: [UInt8] = []

    func append(_ slice: ArraySlice<UInt8>) {
        lock.lock()
        bytes.append(contentsOf: slice)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self)
    }
}

@Suite struct LocalProcessInputGateTests {
    @MainActor
    private func waitFor(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    /// `cat` echoes what reaches it, so the output says whether the process got the bytes.
    @MainActor
    private func catView() async -> (LocalProcessTerminalView, Recorder) {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let output = Recorder()
        view.setProcessBytesHandler { output.append($0) }
        view.startProcess(executable: "/bin/cat", args: [])
        return (view, output)
    }

    @Test @MainActor
    func aGateThatTakesInputKeepsItFromTheProcess() async {
        let (view, output) = await catView()
        let gated = Recorder()
        view.setProcessInputGate { gated.append($0); return true }

        view.send(txt: "held-keys\n")

        #expect(await waitFor { gated.text == "held-keys\n" })
        view.send(source: view, data: Array("released\n".utf8)[...])
        #expect(await waitFor { output.text.contains("released") })
        #expect(!output.text.contains("held-keys"))
        view.terminate()
    }

    @Test @MainActor
    func aGateThatDeclinesOrIsRemovedLetsInputThrough() async {
        let (view, output) = await catView()
        view.setProcessInputGate { _ in false }
        view.send(txt: "declined\n")
        #expect(await waitFor { output.text.contains("declined") })

        view.setProcessInputGate { _ in true }
        view.setProcessInputGate(nil)
        view.send(txt: "ungated\n")
        #expect(await waitFor { output.text.contains("ungated") })
        view.terminate()
    }
}
#endif
