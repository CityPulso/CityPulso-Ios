import Foundation

/**
 * 当前值 + 变化广播（对应 Kotlin `StateFlow`）：`value` 同步可读，`values()` 先发当前值再发每次变化。
 * 用 NSLock 而不是 actor，HTTP 拦截器等同步上下文也能直接读当前值。
 */
public final class StateBroadcast<Value: Sendable & Equatable>: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Value
    private var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]

    public init(_ initial: Value) {
        current = initial
    }

    public var value: Value {
        lock.withLock { current }
    }

    /** 原子地读改写；值没变时不广播（`distinctUntilChanged` 语义）。 */
    public func update(_ transform: (inout Value) -> Void) {
        let (changed, targets): (Value?, [AsyncStream<Value>.Continuation]) = lock.withLock {
            var next = current
            transform(&next)
            guard next != current else { return (nil, []) }
            current = next
            return (next, Array(continuations.values))
        }
        guard let changed else { return }
        targets.forEach { $0.yield(changed) }
    }

    public func set(_ newValue: Value) {
        update { $0 = newValue }
    }

    public func values() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        lock.withLock {
            continuations[id] = continuation
            continuation.yield(current)
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }
}

/** 一次性事件广播（对应 Kotlin `MutableSharedFlow(extraBufferCapacity = 16)`）：只发给已订阅的收听方。 */
public final class EventBroadcast<Event: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Event>.Continuation] = [:]

    public init() {}

    public func emit(_ event: Event) {
        let targets = lock.withLock { Array(continuations.values) }
        targets.forEach { $0.yield(event) }
    }

    public func events() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
        }
        return stream
    }
}
