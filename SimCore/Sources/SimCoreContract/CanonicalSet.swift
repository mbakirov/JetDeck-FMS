import Foundation

/// A set that has a stable JSON form.
///
/// A Swift `Set` has no fixed order. Its default JSON form can change between runs.
/// This wrapper writes the items as a sorted array. Thus two equal snapshots give equal bytes.
@propertyWrapper
public struct CanonicalSet<Element: Hashable & Comparable & Codable & Sendable>: Sendable, Equatable, Codable {
    public var wrappedValue: Set<Element>

    public init(wrappedValue: Set<Element>) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        wrappedValue = Set(try container.decode([Element].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue.sorted())
    }
}

// The order of these enums is the order of their raw values. It is used only for the JSON form.

extension FCUButton: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension EFISButton: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension MCDUAnnunciator: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Sound: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
