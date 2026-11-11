import Foundation

enum JSONCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    static func string<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder().encode(value), as: UTF8.self)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try decoder().decode(type, from: Data(text.utf8))
    }
}
enum Timestamp {
    static func now() -> String { ISO8601DateFormatter().string(from: Date()) }
    static func valid(_ value: String) -> Bool {
        let f = ISO8601DateFormatter()
        if f.date(from: value) != nil { return true }
        f.formatOptions.insert(.withFractionalSeconds)
        return f.date(from: value) != nil
    }
}
enum TextKey {
    static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    // Length-prefixed components prevent delimiter collisions. Meaning is part of the identity.
    static func pair(_ first: String, _ second: String) -> String {
        let a = normalize(first), b = normalize(second)
        return "\(a.utf8.count):\(a)\(b.utf8.count):\(b)"
    }
}
enum LibraryError: LocalizedError {
    case database(String), validation([String]), conflict(String), missing(String)
    var errorDescription: String? {
        switch self {
        case .database(let s): return "数据库错误：\(s)"
        case .validation(let issues): return "资料校验失败（未写入任何数据）：\n" + issues.joined(separator: "\n")
        case .conflict(let s): return "数据冲突：\(s)"
        case .missing(let s): return "未找到：\(s)"
        }
    }
}
