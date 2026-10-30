import PulsoLinkCore
import PulsoLinkUI

private let googleEmailTakenUnverified = "GOOGLE_EMAIL_TAKEN_UNVERIFIED"

/**
 * 登录 / 注册某一步失败时显示的文字（对应 Android `signInErrorText`）。
 * Google 自己的结果有专门文案，其余按通用规则：后端文案 → 类别短句 → [fallback]。
 */
func signInErrorText(_ error: any Error, fallback: String.LocalizationValue) -> String {
    if error is MissingCommunityProfileError {
        return String(localized: "login_no_community_profile")
    }
    if error is GoogleIdTokenMissingError || error is GoogleSignInNotConfiguredError {
        return String(localized: "google_sign_in_failed")
    }
    let uiError = UiError(error)
    if uiError.errCode == googleEmailTakenUnverified {
        return String(localized: "google_email_taken_unverified")
    }
    return uiError.text(fallback: String(localized: fallback))
}
