import Foundation
import GenericJSON

/*
 * 生成的 DTO（Scripts/android_dtos.py）用的编解码辅助，复刻 Android `WireJson` 的语义：
 * - 字段缺失或为 null → 用 Kotlin 属性默认值（`coerceInputValues`）；
 * - `@JsonNames` 的别名也能读；
 * - 编码时 nil 不写（`explicitNulls = false`），等于默认值的也不写（kotlinx 默认 `encodeDefaults = false`）。
 * key 写 Kotlin 属性名：[WireCoding] 的 snake_case 策略负责和 wire 名互转。
 */

/** 任意 JSON（Kotlin `JsonElement`），用于需要显式发 null 的字段。 */
public typealias WireJSON = JSON

extension JSON: @retroactive @unchecked Sendable {}

public struct WireKey: CodingKey, Sendable {
    public let stringValue: String
    public var intValue: Int? { nil }

    public init(_ name: String) {
        stringValue = name
    }

    public init?(stringValue: String) {
        self.stringValue = stringValue
    }

    public init?(intValue: Int) {
        nil
    }
}

extension KeyedDecodingContainer where Key == WireKey {
    /** 依次试 [names]，第一个存在且不为 null 的解出来；都没有返回 nil，由调用方补默认值。 */
    public func wire<T: Decodable>(_ type: T.Type, _ names: String...) throws -> T? {
        for name in names {
            let key = WireKey(name)
            guard contains(key) else { continue }
            if try decodeNil(forKey: key) { return nil }
            return try decode(T.self, forKey: key)
        }
        return nil
    }

    /** 必填字段：缺了就报和 Kotlin 一样的错（MissingFieldException）。 */
    public func wireRequired<T: Decodable>(_ type: T.Type, _ names: String...) throws -> T {
        for name in names {
            let key = WireKey(name)
            if contains(key) { return try decode(T.self, forKey: key) }
        }
        throw DecodingError.keyNotFound(
            WireKey(names[0]),
            DecodingError.Context(codingPath: codingPath, debugDescription: "missing field \(names[0])")
        )
    }
}

extension KeyedEncodingContainer where Key == WireKey {
    /** 有默认值的字段：等于默认值时不写。 */
    public mutating func wire<T: Encodable & Equatable>(_ value: T, _ name: String, default defaultValue: T) throws {
        guard value != defaultValue else { return }
        try encode(value, forKey: WireKey(name))
    }

    /** 可空字段：nil 不写。 */
    public mutating func wireOptional<T: Encodable>(_ value: T?, _ name: String) throws {
        guard let value else { return }
        try encode(value, forKey: WireKey(name))
    }

    /** 没有默认值的非空字段：总是写。 */
    public mutating func wire<T: Encodable>(_ value: T, _ name: String) throws {
        try encode(value, forKey: WireKey(name))
    }
}
