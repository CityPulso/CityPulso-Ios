import Foundation

/** 在 [seconds] 内跑完 [operation]；超时取消它并返回 nil（对应 Kotlin `withTimeoutOrNull`）。 */
public func withTimeoutOrNil<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
