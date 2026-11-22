import Foundation

/// A calendar date without time and time zone (proleptic Gregorian calendar).
/// The type does not use `Calendar` or the system time zone. The result is the same on each device.
public struct CalendarDate: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Returns nil when the date does not exist, for example 2026-02-30.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1, day <= Self.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The date that is `days` days after 1970-01-01.
    public init(daysSince1970 days: Int) {
        // Algorithm "civil_from_days" by Howard Hinnant.
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.year = yoe + era * 400 + (m <= 2 ? 1 : 0)
        self.month = m
        self.day = d
    }

    /// Number of days from 1970-01-01 to this date.
    public var daysSince1970: Int {
        // Algorithm "days_from_civil" by Howard Hinnant.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = month > 2 ? month - 3 : month + 9
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    public func adding(days: Int) -> CalendarDate {
        CalendarDate(daysSince1970: daysSince1970 + days)
    }

    /// ISO 8601 text, for example `2026-10-29`.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Reads ISO 8601 text, for example `2026-10-29`.
    public init?(iso text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}

extension CalendarDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = CalendarDate(iso: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(text)' is not a date in the format YYYY-MM-DD")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// An AIRAC cycle. A cycle is 28 days long. The identifier is the year (2 digits) and the number
/// of the cycle in the year (2 digits), for example `2611`.
public struct AIRACCycle: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// Length of one cycle in days.
    public static let lengthInDays = 28
    /// A known effective date: cycle 2001 started on 2020-01-02. All cycles are a multiple of 28 days from it.
    static let referenceDays = CalendarDate(year: 2020, month: 1, day: 2)!.daysSince1970

    /// The first day of the cycle.
    public let effective: CalendarDate

    /// The cycle that contains `date`.
    public init(containing date: CalendarDate) {
        let offset = date.daysSince1970 - Self.referenceDays
        let index = offset >= 0 ? offset / Self.lengthInDays : (offset - Self.lengthInDays + 1) / Self.lengthInDays
        effective = CalendarDate(daysSince1970: Self.referenceDays + index * Self.lengthInDays)
    }

    /// Reads an identifier such as `2611`. Returns nil when the year has no cycle with this number.
    public init?(ident: String) {
        guard ident.count == 4, ident.allSatisfy(\.isASCII), let value = Int(ident) else { return nil }
        let year = 2000 + value / 100
        let number = value % 100
        guard number >= 1 else { return nil }
        let first = AIRACCycle(containing: CalendarDate(year: year, month: 1, day: 1)!)
        var start = first.effective
        if start.year < year { start = start.adding(days: Self.lengthInDays) }
        let candidate = AIRACCycle(containing: start.adding(days: (number - 1) * Self.lengthInDays))
        guard candidate.effective.year == year else { return nil }
        self = candidate
    }

    /// Year of the effective date.
    public var year: Int { effective.year }

    /// Number of the cycle in its year. The first cycle of the year is 1.
    public var number: Int {
        let dayOfYear = effective.daysSince1970 - CalendarDate(year: effective.year, month: 1, day: 1)!.daysSince1970
        return dayOfYear / Self.lengthInDays + 1
    }

    /// Identifier, for example `2611`.
    public var ident: String {
        String(format: "%02d%02d", year % 100, number)
    }

    /// The last day of the cycle. The next cycle starts on the day after.
    public var lastDay: CalendarDate { effective.adding(days: Self.lengthInDays - 1) }

    public var next: AIRACCycle { AIRACCycle(containing: effective.adding(days: Self.lengthInDays)) }
    public var previous: AIRACCycle { AIRACCycle(containing: effective.adding(days: -1)) }

    public var description: String { ident }

    public static func < (lhs: AIRACCycle, rhs: AIRACCycle) -> Bool {
        lhs.effective < rhs.effective
    }
}

extension AIRACCycle: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let cycle = AIRACCycle(ident: text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(text)' is not an AIRAC cycle")
        }
        self = cycle
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ident)
    }
}

/// Identity of a navigation database. A flight recording stores it.
/// A replay with a different database can give different snapshots, so the replay rejects it.
public struct NavDataIdentity: Sendable, Codable, Hashable, CustomStringConvertible {
    public var cycle: AIRACCycle
    /// Version of the database schema.
    public var schemaVersion: Int
    /// Version of the converter that made the database. A new version can change the content.
    public var builderVersion: Int
    /// SHA-256 (hexadecimal, lower case) of the source file, for example FAACIFP18.
    public var sourceSHA256: String

    public init(cycle: AIRACCycle, schemaVersion: Int, builderVersion: Int, sourceSHA256: String) {
        self.cycle = cycle
        self.schemaVersion = schemaVersion
        self.builderVersion = builderVersion
        self.sourceSHA256 = sourceSHA256
    }

    public var description: String {
        "AIRAC \(cycle.ident), schema \(schemaVersion), builder \(builderVersion), source \(sourceSHA256.prefix(12))"
    }
}
