import BetterCodable
import Foundation

/** 成功响应体 `{ data: T }`（与 WEB `DataResponse<T>` 一致）。 */
public struct DataResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let data: T?

    /** 成功响应体应含 `data`；缺失时抛错（对应 WEB `dataFromResponse`）。 */
    public func dataOrThrow(_ context: String) throws -> T {
        guard let data else { throw MissingDataError(context: context) }
        return data
    }
}

public struct MissingDataError: Error, Sendable, CustomStringConvertible {
    public let context: String
    public var description: String { "API response missing data (\(context))" }
}

/** 列表 + 总数（与 WEB `ListDTOWithTotalNumber<T>` 一致，offset/limit 分页返回）。 */
public struct ListWithTotal<T: Codable & Sendable>: Codable, Sendable {
    @DefaultEmptyArray public var items: [T]
    @DefaultZero public var total: Int
}

/** 字符串游标列表（与 WEB `ListDTOWithNextCursor<T>` 一致）。 */
public struct ListWithNextCursor<T: Codable & Sendable>: Codable, Sendable {
    @DefaultEmptyArray public var items: [T]
    public var nextCursor: String?
}
