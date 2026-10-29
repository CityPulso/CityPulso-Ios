/**
 * 一个查询在页面上的状态（对应 Android `Loadable` / react-query `{ data, isLoading, error }`）。
 * 后台刷新不会把已经上屏的数据换成加载中。
 */
public struct Loadable<T: Sendable>: Sendable {
    public var data: T?
    public var isLoading: Bool
    public var error: UiError?

    public init(data: T? = nil, isLoading: Bool = true, error: UiError? = nil) {
        self.data = data
        self.isLoading = isLoading
        self.error = error
    }

    public func reduce(_ response: QueryResponse<T>) -> Loadable<T> {
        switch response {
        case let .data(value): Loadable(data: value, isLoading: false)
        case .loading: Loadable(data: data, isLoading: data == nil)
        case let .error(error): Loadable(data: data, isLoading: false, error: error)
        }
    }

    /** 一次性加载失败：保留已有数据（Android `settle` 的失败分支）。 */
    public func failed(_ error: any Error) -> Loadable<T> {
        Loadable(data: data, isLoading: false, error: UiError(error))
    }

    public func map<R: Sendable>(_ transform: (T) -> R) -> Loadable<R> {
        Loadable<R>(data: data.map(transform), isLoading: isLoading, error: error)
    }
}
