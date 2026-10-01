//
//  Locked.swift
//  SwiftTerm
//
//  A small synchronized state container for state that does not require the
//  FIFO fairness guarantee of TerminalLock.
//

#if !SWIFTTERM_EMBEDDED
import Foundation
#if canImport(Synchronization)
import Synchronization
#endif

/// Owns one value behind a non-recursive lock.
///
/// The unchecked conformance is limited to this synchronization primitive.
/// Callers must not expose mutable value storage from `withLock`. They can copy
/// a stable reference when that reference has separate synchronization and
/// does not escape the owning API.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init (_ value: Value) {
        self.value = value
    }

    @discardableResult
    func withLock<Result> (_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

private protocol VoidCallbackStorage: Sendable {
    func replace(with body: (@Sendable () -> Void)?)
    var current: (@Sendable () -> Void)? { get }
    func call()
}

private final class NSLockedVoidCallbackStorage: VoidCallbackStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?

    init(_ body: (@Sendable () -> Void)? = nil) {
        callback = body
    }

    func replace(with body: (@Sendable () -> Void)?) {
        lock.lock()
        callback = body
        lock.unlock()
    }

    /// Returns the callback for APIs that must expose a stored function.
    var current: (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return callback
    }

    func call() {
        lock.lock()
        let current = callback
        lock.unlock()
        current?()
    }
}

#if canImport(Synchronization)
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
private final class MutexVoidCallbackStorage: VoidCallbackStorage, Sendable {
    private final class Callback: Sendable {
        let body: @Sendable () -> Void

        init(_ body: @escaping @Sendable () -> Void) {
            self.body = body
        }

        func call() {
            body()
        }
    }

    private let callback: Mutex<Callback?>

    init(_ body: (@Sendable () -> Void)? = nil) {
        callback = Mutex(body.map(Callback.init))
    }

    func replace(with body: (@Sendable () -> Void)?) {
        let next = body.map(Callback.init)
        callback.withLock { $0 = next }
    }

    var current: (@Sendable () -> Void)? {
        callback.withLock { $0 }?.body
    }

    func call() {
        let current = callback.withLock { $0 }
        current?.call()
    }
}
#endif

/// Stores a replaceable callback without passing the function value through a
/// generic container. Uses `Mutex` when the build and runtime support it, and
/// falls back to `NSLock` on older systems.
final class LockedVoidCallback: Sendable {
    private let storage: any VoidCallbackStorage

    init(_ body: (@Sendable () -> Void)? = nil) {
#if canImport(Synchronization)
        if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
            storage = MutexVoidCallbackStorage(body)
        } else {
            storage = NSLockedVoidCallbackStorage(body)
        }
#else
        storage = NSLockedVoidCallbackStorage(body)
#endif
    }

    func replace(with body: (@Sendable () -> Void)?) {
        storage.replace(with: body)
    }

    /// Returns the callback for APIs that must expose a stored function.
    var current: (@Sendable () -> Void)? {
        storage.current
    }

    func call() {
        storage.call()
    }
}

/// Stores the replaceable process-bytes callback with its concrete function type.
///
/// **Never keep a closure in `Locked<Value>` and read it with `withLock { $0 }`.** That body is
/// an `inout` access through a generic container, so the closure is reabstracted on the way out
/// and again on the write-back, and the stored value grows by two thunks on every access. Read
/// once per output batch, the chain reached the IO reader's stack limit after about 75 minutes
/// of a live session and crashed it (EXC_BAD_ACCESS, hundreds of alternating
/// `ArraySlice<UInt8>` thunks, 2026-10-01). This is the same reason `LockedVoidCallback` exists.
final class LockedBytesCallback: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (ArraySlice<UInt8>) -> Void)?

    func replace(with body: (@Sendable (ArraySlice<UInt8>) -> Void)?) {
        lock.lock()
        callback = body
        lock.unlock()
    }

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return callback != nil
    }

    func call(_ bytes: ArraySlice<UInt8>) {
        lock.lock()
        let current = callback
        lock.unlock()
        current?(bytes)
    }
}

#endif // !SWIFTTERM_EMBEDDED
