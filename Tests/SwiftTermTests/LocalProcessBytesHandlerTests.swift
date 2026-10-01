//
//  LocalProcessBytesHandlerTests.swift
//
//  In SwiftTerm 2 the LocalProcess delegate is a private adapter, so a subclass
//  override of dataReceived(slice:) is never called. setProcessBytesHandler is
//  how a host sees the raw output stream; these drive a real PTY through it.
//
#if os(macOS)
import AppKit
import Foundation
import Testing

@testable import SwiftTerm

private final class ByteSink: @unchecked Sendable {
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

@Suite struct LocalProcessBytesHandlerTests {
    @MainActor
    private func waitFor(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    @Test @MainActor
    func handlerReceivesProcessOutputForAWindowlessView() async {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let sink = ByteSink()
        view.setProcessBytesHandler { sink.append($0) }
        view.startProcess(executable: "/bin/sh", args: ["-c", "printf 'holidu-bytes-hook'"])

        #expect(await waitFor { sink.text.contains("holidu-bytes-hook") })
        #expect(view.diagnostics.bytesFed >= "holidu-bytes-hook".utf8.count)
    }

    @Test @MainActor
    func removingTheHandlerStopsDelivery() async {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let sink = ByteSink()
        view.setProcessBytesHandler { sink.append($0) }
        view.setProcessBytesHandler(nil)
        view.startProcess(executable: "/bin/sh", args: ["-c", "printf 'after-removal'"])

        #expect(await waitFor { view.diagnostics.bytesFed > 0 })
        #expect(sink.text.isEmpty)
    }

    /// The handler is read on every output batch, for the life of the session. Storing it in the
    /// generic `Locked<Value>` and reading it with `withLock { $0 }` grew the closure by two
    /// reabstraction thunks per read, and a live session overflowed the IO reader's stack after
    /// about 75 minutes. Far more batches than that, on the real delivery path, must stay flat.
    @Test @MainActor
    func handlerSurvivesManyBatchesWithoutGrowing() {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        let sink = ByteSink()
        view.setProcessBytesHandler { sink.append($0) }
        let batch: [UInt8] = Array("x".utf8)
        for _ in 0..<300_000 {
            view.processAdapter.dataReceived(slice: batch[...])
        }
        #expect(sink.text.utf8.count == 300_000)
    }

    @Test @MainActor
    func bracketedPasteModeTracksDecset2004() async {
        let view = LocalProcessTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 320))
        #expect(view.bracketedPasteMode == false)
        view.feed(text: "\u{1b}[?2004h")
        #expect(view.bracketedPasteMode == true)
        view.feed(text: "\u{1b}[?2004l")
        #expect(view.bracketedPasteMode == false)
    }
}
#endif
