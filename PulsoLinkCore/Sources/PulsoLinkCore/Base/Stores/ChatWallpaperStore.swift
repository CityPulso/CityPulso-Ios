import Foundation

/**
 * 聊天壁纸（Android `ChatWallpaperStore`）：只存在本机，按会话 id 存一张图（`Application Support/chat_wallpapers/<id>.jpg`），
 * 从不上传；登出时全部删掉。
 */
public final class ChatWallpaperStore: LogoutClearable, @unchecked Sendable {
    private static let indexKey = "pulso.chatWallpapers"
    public let paths: StateBroadcast<[String: String]>
    private let defaults: UserDefaults
    private let directory: URL

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        directory = support.appendingPathComponent("chat_wallpapers", isDirectory: true)
        paths = StateBroadcast(defaults.dictionary(forKey: Self.indexKey) as? [String: String] ?? [:])
    }

    public func path(_ conversationId: String) -> String? { paths.value[conversationId] }

    public func set(_ conversationId: String, imageData: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(conversationId).jpg")
        try imageData.write(to: file, options: .atomic)
        paths.update { $0[conversationId] = file.path }
        defaults.set(paths.value, forKey: Self.indexKey)
    }

    public func clear(_ conversationId: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(conversationId).jpg"))
        paths.update { $0[conversationId] = nil }
        defaults.set(paths.value, forKey: Self.indexKey)
    }

    /** 本机上的壁纸：几张、多少字节（设置里的本地数据页）。 */
    public func usage() -> (count: Int, bytes: Int64) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (files.count, bytes)
    }

    public func onLogout() async throws {
        try? FileManager.default.removeItem(at: directory)
        paths.set([:])
        defaults.removeObject(forKey: Self.indexKey)
    }
}
