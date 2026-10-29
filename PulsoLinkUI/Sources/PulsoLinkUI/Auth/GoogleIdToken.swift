import GoogleSignIn
import SwiftUI
import UIKit

/** Info.plist 里没有 `GIDClientID`（project.yml 没给这个 App 配 Google iOS client）。 */
public struct GoogleSignInNotConfiguredError: Error {}

/** Google 登录成功却没给 ID token。 */
public struct GoogleIdTokenMissingError: Error {}

/**
 * 「使用 Google 登录」（对应 Android `requestGoogleIdToken`）：Google 官方 iOS SDK 弹出登录，
 * 返回发给 POST /auth/login/with-google 的 ID token。
 *
 * iOS client（Info.plist `GIDClientID` + 回跳 URL scheme）标识本 App；[serverClientID] 是后端
 * `/auth/env` 给的 web client ID，ID token 签给它，后端才验得过。
 */
@MainActor
public enum GoogleIdToken {
    /** - Returns: nil 表示用户取消，什么都不用提示。 */
    public static func request(serverClientID: String) async throws -> String? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !clientID.isEmpty else {
            throw GoogleSignInNotConfiguredError()
        }
        guard let presenter = topViewController() else { throw GoogleSignInNotConfiguredError() }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let token = result.user.idToken?.tokenString else { throw GoogleIdTokenMissingError() }
            return token
        } catch let error as GIDSignInError where error.code == .canceled {
            return nil
        }
    }

    /** Google 登录页跳回 App 的 URL（`.onOpenURL` 里调用）。 */
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
