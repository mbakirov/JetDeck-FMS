import Foundation

/// A JSON document as a tree. The comparison of snapshots works on this tree.
/// Thus the comparison needs no change when the contract gets new fields.
public enum JSONValue: Sendable, Equatable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Short text for reports.
    public var summary: String {
        switch self {
        case .null: "null"
        case .bool(let value): String(value)
        case .number(let value): value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .string(let value): "\"\(value)\""
        case .array(let items): "[\(items.count) items]"
        case .object(let fields): "{\(fields.count) fields}"
        }
    }
}
