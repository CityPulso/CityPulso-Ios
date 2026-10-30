import Foundation

/**
 * 离线优先的查询（Android `PersistedQuery`，Store5 + Room）：本地库是唯一来源，网络只负责刷新。
 *
 * - [stream] 先推本地已有的行，同时拉一次网络写回本地；之后本地每变一次就推一次。
 * - [invalidates] 每来一次脉冲，活跃的 stream 重拉网络（本地旧行留着显示）。
 * - 拉网络失败推 `.error`，已有的本地行不受影响。
 */
public final class PersistedQuery<Key: Hashable & Sendable, Network: Sendable, Output: Sendable>: Sendable {
    private let invalidates: @Sendable () -> AsyncStream<Void>
    private let fetcher: @Sendable (Key) async throws -> Network
    private let reader: @Sendable (Key) -> AsyncStream<Output?>
    private let writer: @Sendable (Key, Network) async throws -> Void
    private let deleter: @Sendable (Key) async throws -> Void
    private let deleteAller: @Sendable () async throws -> Void

    public init(
        invalidates: @escaping @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } },
        fetcher: @escaping @Sendable (Key) async throws -> Network,
        reader: @escaping @Sendable (Key) -> AsyncStream<Output?>,
        writer: @escaping @Sendable (Key, Network) async throws -> Void,
        delete: @escaping @Sendable (Key) async throws -> Void,
        deleteAll: @escaping @Sendable () async throws -> Void
    ) {
        self.invalidates = invalidates
        self.fetcher = fetcher
        self.reader = reader
        self.writer = writer
        deleter = delete
        deleteAller = deleteAll
    }

    public func stream(_ key: Key) -> AsyncStream<QueryResponse<Output>> {
        AsyncStream { continuation in
            let task = Task {
                let pulses = invalidates()
                continuation.yield(.loading)
                let local = Task {
                    for await value in reader(key) {
                        if let value { continuation.yield(.data(value)) }
                    }
                }
                await refresh(key, into: continuation)
                for await _ in pulses {
                    await refresh(key, into: continuation)
                }
                local.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /** 本地有就用本地，否则拉一次网络。 */
    public func get(_ key: Key) async throws -> Output {
        if let cached = await firstLocal(key) { return cached }
        return try await fresh(key)
    }

    /** 总是拉网络、写回本地，再返回本地的新行。 */
    public func fresh(_ key: Key) async throws -> Output {
        try await writer(key, fetcher(key))
        guard let value = await firstLocal(key) else { throw CancellationError() }
        return value
    }

    public func delete(_ key: Key) async throws {
        try await deleter(key)
    }

    public func deleteAll() async throws {
        try await deleteAller()
    }

    private func firstLocal(_ key: Key) async -> Output? {
        for await value in reader(key) {
            return value
        }
        return nil
    }

    private func refresh(_ key: Key, into continuation: AsyncStream<QueryResponse<Output>>.Continuation) async {
        do {
            try await writer(key, fetcher(key))
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            continuation.yield(.error(UiError(error)))
        }
    }
}
