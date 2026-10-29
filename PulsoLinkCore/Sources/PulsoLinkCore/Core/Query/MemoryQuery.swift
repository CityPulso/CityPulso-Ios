import Foundation

/** 一次读的结果（对应 Store5 `StoreReadResponse` 的 Loading / Data / Error）。 */
public enum QueryResponse<Output: Sendable>: Sendable {
    case loading
    case data(Output)
    case error(UiError)
}

/**
 * 内存查询缓存（对应 Android `MemoryQuery` / react-query）：每个 key 一份缓存，[ttl] 内算新鲜。
 *
 * - [stream] 有缓存先发缓存，再按需拉网络；同一 key 别处写入的新值也会推给活跃的 stream。
 * - [invalidates] 每来一次脉冲就清空缓存，活跃的 stream 立刻重拉（`invalidateQueries` + `refetchType: "active"`）。
 * - 同一 key 同时只有一个请求在飞，后来的调用方共用它的结果。
 *
 * Swift 没有 Store5 这样的成熟包，这里只保留 Android 用到的那部分语义。
 */
public final class MemoryQuery<Key: Hashable & Sendable, Output: Sendable>: Sendable {
    private let storage: Storage
    private let invalidates: @Sendable () -> AsyncStream<Void>
    private let listener: Task<Void, Never>

    public init(
        ttl: Duration = .seconds(300),
        maxSize: Int = 64,
        invalidates: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        fetcher: @escaping @Sendable (Key) async throws -> Output
    ) {
        let storage = Storage(ttl: ttl, maxSize: maxSize, fetcher: fetcher)
        self.storage = storage
        self.invalidates = invalidates
        let pulses = invalidates()
        listener = Task {
            for await _ in pulses {
                await storage.clear()
            }
        }
    }

    deinit {
        listener.cancel()
    }

    /** 新鲜缓存直接返回，否则拉网络。 */
    public func get(_ key: Key) async throws -> Output {
        try await storage.get(key)
    }

    /** 总是拉网络并写入缓存。 */
    public func fresh(_ key: Key) async throws -> Output {
        try await storage.fetch(key)
    }

    public func clear() async {
        await storage.clear()
    }

    /** 直接改写缓存（乐观更新 / 写操作返回了新值），活跃的 stream 会收到。 */
    public func set(_ key: Key, _ value: Output) async {
        await storage.write(key, value)
    }

    /**
     * 订阅一个 key：有缓存先发 `.data`；没有缓存、缓存过期或 [refresh] 时发 `.loading` 再拉网络。
     * 之后每次失效都重拉，直到调用方取消（随页面 `.task` 结束）。
     */
    public func stream(_ key: Key, refresh: Bool = true) -> AsyncStream<QueryResponse<Output>> {
        let storage = storage
        let pulses = invalidates()
        return AsyncStream { continuation in
            let task = Task {
                let id = await storage.subscribe(key, continuation)
                await storage.load(key, refresh: refresh, into: continuation)
                for await _ in pulses {
                    await storage.clear()
                    await storage.load(key, refresh: true, into: continuation)
                }
                // 没有失效来源（或它结束了）也要一直订阅，别处写入的新值照样推过来。
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                }
                await storage.unsubscribe(key, id)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private actor Storage {
        private struct Entry {
            let value: Output
            let writtenAt: ContinuousClock.Instant
        }

        private let ttl: Duration
        private let maxSize: Int
        private let fetcher: @Sendable (Key) async throws -> Output
        private let clock = ContinuousClock()
        private var entries: [Key: Entry] = [:]
        /** 写入顺序，超出 [maxSize] 时先丢最旧的。 */
        private var order: [Key] = []
        private var inFlight: [Key: Task<Output, any Error>] = [:]
        private var subscribers: [Key: [UUID: AsyncStream<QueryResponse<Output>>.Continuation]] = [:]

        init(ttl: Duration, maxSize: Int, fetcher: @escaping @Sendable (Key) async throws -> Output) {
            self.ttl = ttl
            self.maxSize = maxSize
            self.fetcher = fetcher
        }

        func get(_ key: Key) async throws -> Output {
            if let entry = entries[key], clock.now - entry.writtenAt < ttl {
                return entry.value
            }
            return try await fetch(key)
        }

        func fetch(_ key: Key) async throws -> Output {
            if let running = inFlight[key] {
                return try await running.value
            }
            let fetcher = fetcher
            let task = Task { try await fetcher(key) }
            inFlight[key] = task
            defer { inFlight[key] = nil }
            let value = try await task.value
            write(key, value)
            return value
        }

        func load(_ key: Key, refresh: Bool, into continuation: AsyncStream<QueryResponse<Output>>.Continuation) async {
            let cached = entries[key]
            if let cached {
                continuation.yield(.data(cached.value))
                guard refresh || clock.now - cached.writtenAt >= ttl else { return }
            } else {
                continuation.yield(.loading)
            }
            do {
                // 成功时 write 已经推给全部订阅方（包括这一个）。
                _ = try await fetch(key)
            } catch is CancellationError {
                return
            } catch {
                continuation.yield(.error(UiError(error)))
            }
        }

        func write(_ key: Key, _ value: Output) {
            if entries[key] == nil {
                order.append(key)
                if order.count > maxSize {
                    entries[order.removeFirst()] = nil
                }
            }
            entries[key] = Entry(value: value, writtenAt: clock.now)
            subscribers[key]?.values.forEach { $0.yield(.data(value)) }
        }

        func clear() {
            entries.removeAll()
            order.removeAll()
        }

        func subscribe(_ key: Key, _ continuation: AsyncStream<QueryResponse<Output>>.Continuation) -> UUID {
            let id = UUID()
            subscribers[key, default: [:]][id] = continuation
            return id
        }

        func unsubscribe(_ key: Key, _ id: UUID) {
            subscribers[key]?[id] = nil
        }
    }
}
