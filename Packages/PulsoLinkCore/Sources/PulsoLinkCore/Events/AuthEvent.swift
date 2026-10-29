import Foundation

/** 认证跨模块事件——与 WEB `events/auth.ts` 全量对齐。 */
public enum AuthEvent: Sendable, Equatable {
    case loginSuccess(accountId: String)
    case logout(accountId: String?)
    /** 账号资料更新成功（档案 PATCH / 偏好上传等）。 */
    case updateAccountSuccess
    /** 邮箱列表失效；accountId 为 nil 表示当前账号。 */
    case invalidateEmails(accountId: String?)
    /** 身份列表失效：必须精确带上账号与档位，禁止靠订阅方回落猜测。 */
    case invalidateProfiles(accountId: String, kind: ProfileKind)
    /** moderation 申请列表失效。 */
    case invalidateModerationApplications
    /** 申请审核结果：通过时需刷新对应档位身份列表。 */
    case applicationResolved(outcome: String, kind: ProfileKind)
}

public typealias AuthEventBus = EventBroadcast<AuthEvent>
