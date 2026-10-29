import Foundation
import Testing
@testable import PulsoLinkCore

struct APIErrorTests {
    @Test func readsBackendErrorBody() {
        let body = Data(#"{"err_code":"INVALID_TOKEN","message":"Token expired","trace_id":"t-1"}"#.utf8)
        let error = APIError(status: 401, body: body)
        #expect(error.status == 401)
        #expect(error.errCode == ErrorCodes.invalidToken)
        #expect(error.message == "Token expired")
        #expect(error.traceId == "t-1")
    }

    @Test func dropsGatewayNoise() {
        let html = APIError(status: 502, body: Data("<html><body>Bad Gateway</body></html>".utf8))
        #expect(html.message == nil)
        let gateway = APIError(status: 502, body: Data(#"{"message":"Bad Gateway"}"#.utf8))
        #expect(gateway.message == nil)
    }

    @Test func forceLogoutCodes() {
        #expect(APIError(status: 403, errCode: ErrorCodes.authorityProfileInsufficientRole).shouldImmediateForceLogout)
        #expect(!APIError(status: 401, errCode: ErrorCodes.invalidToken).shouldImmediateForceLogout)
        #expect(!APIError(status: 500).shouldImmediateForceLogout)
    }
}
