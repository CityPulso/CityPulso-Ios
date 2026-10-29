/**
 * 在 main actor 上同时跑几段长期订阅，等它们都结束；调用方被取消（页面 `.task` 结束）时一起取消。
 * 用来代替 `withTaskGroup` + `@MainActor` 子任务：Swift 6 的隔离检查器对那种写法会报内部错误。
 */
@MainActor
func concurrently(_ operations: [@MainActor () async -> Void]) async {
    let tasks = operations.map { operation in Task { await operation() } }
    await withTaskCancellationHandler {
        for task in tasks { await task.value }
    } onCancel: {
        tasks.forEach { $0.cancel() }
    }
}
