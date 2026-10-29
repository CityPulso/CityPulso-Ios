import Foundation
import Testing
@testable import PulsoLinkCore

private let host = "asset.stub"

@Suite(.serialized)
struct AssetUploadTests {
    init() {
        StubProtocol.reset(host)
    }

    private func repository() -> AssetRepository {
        let client = APIClient(config: stubConfig(host: host), interceptor: nil, configuration: StubProtocol.configuration)
        return AssetRepository(api: AssetAPI(client: client), storage: client)
    }

    @Test func preparesPutsThenConfirms() async throws {
        StubProtocol.serve(host) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/asset/images/upload-url"):
                (200, #"{"data":{"image_id":"img-1","upload_url":"https://asset.stub/bucket/tmp/img-1","object_key":"tmp/img-1"}}"#)
            case ("PUT", "/bucket/tmp/img-1"): (200, "")
            case ("POST", "/api/asset/images/confirm"): (204, "")
            default: (404, "")
            }
        }
        let id = try await repository().uploadImage(Data([1, 2, 3]), fileName: "a.jpg", mimeType: "image/jpeg", category: .avatar)
        #expect(id == "img-1")
        let requests = StubProtocol.received(host)
        #expect(requests.map(\.httpMethod) == ["POST", "PUT", "POST"])
        #expect(requests[1].value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func storageRejectionThrowsWithStatus() async throws {
        StubProtocol.serve(host) { request in
            request.httpMethod == "PUT"
                ? (403, "")
                : (200, #"{"data":{"image_id":"img-1","upload_url":"https://asset.stub/bucket/x","object_key":"x"}}"#)
        }
        await #expect(throws: ImageUploadError.self) {
            _ = try await repository().putImage(Data(), fileName: "a.png", mimeType: "image/png", category: .background)
        }
    }

    @Test func chatConfirmUsesTheTypedIdKey() throws {
        let body = String(decoding: try WireCoding.encoder.encode(
            ConfirmChatAssetRequest(assetType: .video, assetId: "v1", assetCategory: .message)
        ), as: UTF8.self)
        #expect(body.contains(#""video_id":"v1""#))
        #expect(body.contains(#""asset_type":"video""#))
        #expect(body.contains(#""asset_category":"message""#))
    }

    @Test func imageURLs() {
        let base = URL(string: "https://pulsolink.com/api")!
        #expect(ImageURLs.image("abc", base: base)?.absoluteString == "https://pulsolink.com/api/asset/images/abc/file")
        #expect(ImageURLs.image("https://x/y.png", base: base)?.absoluteString == "https://x/y.png")
        #expect(ImageURLs.image(" ", base: base) == nil)
        #expect(ImageURLs.attachment("f", type: .file, base: base)?.absoluteString == "https://pulsolink.com/api/asset/files/f/file")
    }
}
