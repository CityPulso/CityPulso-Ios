import Nuke
import PulsoLinkCore

/** Nuke 的磁盘缓存（只有字节数）和内存缓存，设置页「清除本地数据」的图片一行（Android `ImageCacheDataSource`）。 */
public struct ImageCacheDataSource: LocalDataSource {
    public let kind = LocalDataKind.images

    public init() {}

    public func usage() async throws -> LocalDataUsage {
        let cache = ImagePipeline.shared.configuration.dataCache as? DataCache
        return LocalDataUsage(count: nil, bytes: cache.map { Int64($0.totalSize) })
    }

    public func clear() async throws {
        ImagePipeline.shared.cache.removeAll()
    }
}
