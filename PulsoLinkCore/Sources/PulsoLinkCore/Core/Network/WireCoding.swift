import BetterCodable
import Foundation

/**
 * API 与实时推送共用的 wire 格式（对应 Android `WireJson`）：snake_case 键、忽略未知字段、
 * nil 字段不写出。非法枚举值回落默认值见 [WireEnum]；缺省字段默认值用 BetterCodable 的 `@Default*`。
 */
public enum WireCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/**
 * 闭集 wire 枚举：rawValue 就是 wire 字符串；解码遇到未知值回落 [fallback]
 *（对应 kotlinx `coerceInputValues` + 各枚举的 `fromWire`）。
 */
public protocol WireEnum: RawRepresentable, Codable, CaseIterable, Sendable, Hashable where RawValue == String {
    static var fallback: Self { get }
}

extension WireEnum {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? Self.fallback
    }

    public static func fromWire(_ raw: String?) -> Self {
        raw.flatMap(Self.init(rawValue:)) ?? fallback
    }
}

/* ---------- BetterCodable 缺省值策略（kotlinx 的属性默认值） ---------- */

public enum DefaultZeroStrategy: DefaultCodableStrategy {
    public static var defaultValue: Int { 0 }
}

/** 缺失时为 0 的整数字段（如 `total`）。 */
public typealias DefaultZero = DefaultCodable<DefaultZeroStrategy>

public enum DefaultWireStrategy<E: WireEnum>: DefaultCodableStrategy {
    public static var defaultValue: E { E.fallback }
}

/** 缺失时为枚举 [WireEnum.fallback] 的字段。 */
public typealias DefaultWire<E: WireEnum> = DefaultCodable<DefaultWireStrategy<E>>

// BetterCodable 早于 Swift 并发，没标 Sendable；`DefaultCodable` 只是包着一个值的 struct，值 Sendable 它就 Sendable。
extension DefaultCodable: @unchecked @retroactive Sendable where Default.DefaultValue: Sendable {}
