import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/**
 * 给用户看的失败类别。原始异常文字不进 UI；每个页面按类别显示本地化标题 / 说明
 *（对应 Android `LoadErrorKind`）。
 */
public enum LoadErrorKind: Sendable, Hashable {
    case notFound
    case unauthorized
    case timeout
    case offline
    case server
    case unknown
}

/**
 * 可直接显示的失败（对应 Android `UiError`）。
 * [message] 只会是后端业务文案（已去掉网关原文）；网络层错误没有 message，它们的文字永远不上屏。
 */
public struct UiError: Sendable, Hashable {
    public let kind: LoadErrorKind
    public let message: String?
    public let errCode: String?

    public init(kind: LoadErrorKind, message: String? = nil, errCode: String? = nil) {
        self.kind = kind
        self.message = message
        self.errCode = errCode
    }

    public init(_ error: any Error) {
        if let api = error as? APIError {
            self.init(kind: Self.kind(status: api.status), message: api.message, errCode: api.errCode)
        } else if let url = error as? URLError {
            self.init(kind: url.code == .timedOut ? .timeout : .offline)
        } else {
            self.init(kind: .unknown)
        }
    }

    private static func kind(status: Int) -> LoadErrorKind {
        switch status {
        case 0: .offline
        case 404: .notFound
        case 401, 403: .unauthorized
        case 408, 504: .timeout
        case 500...599: .server
        default: .unknown
        }
    }
}
