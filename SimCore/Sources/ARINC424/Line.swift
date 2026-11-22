import Foundation

/// An error in one field of an ARINC 424 record.
public struct ARINC424Error: Error, Sendable, Equatable, CustomStringConvertible {
    /// Line number in the file. The first line is 1.
    public var line: Int
    public var field: String
    /// Columns of the field, 1-based as in the ARINC 424 specification.
    public var columns: ClosedRange<Int>
    public var value: String
    public var reason: String

    public init(line: Int, field: String, columns: ClosedRange<Int>, value: String, reason: String) {
        self.line = line
        self.field = field
        self.columns = columns
        self.value = value
        self.reason = reason
    }

    public var description: String {
        "line \(line): \(field) (columns \(columns.lowerBound)-\(columns.upperBound)) '\(value)': \(reason)"
    }
}

/// A point on the earth in degrees. North and east are positive.
public struct ARINC424Coordinate: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A course or bearing. ARINC 424 gives a magnetic value in tenths of a degree (`0438` = 43.8°)
/// or a true value in whole degrees with the letter T (`044T`).
public struct ARINC424Bearing: Sendable, Equatable {
    public var degrees: Double
    public var isTrue: Bool

    public init(degrees: Double, isTrue: Bool) {
        self.degrees = degrees
        self.isTrue = isTrue
    }
}

/// The field "route distance, holding distance or time" of a procedure leg.
public enum ARINC424DistanceOrTime: Sendable, Equatable {
    case nauticalMiles(Double)
    case minutes(Double)
}

/// One record of 132 columns.
///
/// Column numbers in this module are 1-based, as in the ARINC 424 specification.
public struct ARINC424Line: Sendable {
    public static let length = 132

    /// Line number in the file. The first line is 1.
    public let number: Int
    public let bytes: [UInt8]

    /// Returns nil when the line does not have 132 characters. A trailing carriage return is removed.
    public init?(number: Int, bytes: some Collection<UInt8>) {
        var array = Array(bytes)
        if array.last == 0x0D { array.removeLast() }
        guard array.count == Self.length else { return nil }
        self.number = number
        self.bytes = array
    }

    public init?(number: Int = 1, _ text: String) {
        self.init(number: number, bytes: Array(text.utf8))
    }

    /// The byte at a column.
    @inline(__always)
    public func byte(_ column: Int) -> UInt8 {
        bytes[column - 1]
    }

    /// The character at a column.
    public func character(_ column: Int) -> Character {
        Character(Unicode.Scalar(byte(column)))
    }

    /// The exact text of the columns.
    public func raw(_ columns: ClosedRange<Int>) -> String {
        String(decoding: bytes[(columns.lowerBound - 1)..<columns.upperBound], as: UTF8.self)
    }

    /// The text of the columns without spaces at the start and at the end.
    public func text(_ columns: ClosedRange<Int>) -> String {
        var start = columns.lowerBound - 1
        var end = columns.upperBound
        while start < end, bytes[start] == 0x20 { start += 1 }
        while end > start, bytes[end - 1] == 0x20 { end -= 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// The text of the columns, or nil when all columns are spaces.
    public func optionalText(_ columns: ClosedRange<Int>) -> String? {
        let value = text(columns)
        return value.isEmpty ? nil : value
    }

    /// True when all columns are spaces.
    public func isBlank(_ columns: ClosedRange<Int>) -> Bool {
        bytes[(columns.lowerBound - 1)..<columns.upperBound].allSatisfy { $0 == 0x20 }
    }

    public func error(_ field: String, _ columns: ClosedRange<Int>, _ reason: String) -> ARINC424Error {
        ARINC424Error(line: number, field: field, columns: columns, value: raw(columns), reason: reason)
    }

    // MARK: Numbers

    /// An integer with an optional sign. Spaces at the start and at the end are permitted.
    /// Returns nil when the field is blank.
    public func integer(_ field: String, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> Int? {
        let value = text(columns)
        if value.isEmpty { return nil }
        guard let number = Self.parseInteger(value) else { throw error(field, columns, "not an integer") }
        return number
    }

    public func requiredInteger(_ field: String, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> Int {
        guard let value = try integer(field, columns) else { throw error(field, columns, "the field is blank") }
        return value
    }

    /// A number with an implied decimal point: `scale` is the number of decimal places.
    public func decimal(_ field: String, _ columns: ClosedRange<Int>, scale: Int) throws(ARINC424Error) -> Double? {
        guard let value = try integer(field, columns) else { return nil }
        return Double(value) / pow(10, Double(scale))
    }

    static func parseInteger(_ text: String) -> Int? {
        var digits = Substring(text)
        var sign = 1
        if let first = digits.first, first == "+" || first == "-" {
            sign = first == "-" ? -1 : 1
            digits = digits.dropFirst()
            // Some fields have spaces between the sign and the digits.
            while digits.first == " " { digits = digits.dropFirst() }
        }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(digits) else { return nil }
        return sign * value
    }

    // MARK: Coordinates

    /// Latitude `NDDMMSSss` (9 columns) and longitude `EDDDMMSSss` (10 columns).
    /// Returns nil when both fields are blank.
    public func coordinate(_ field: String, latitude: ClosedRange<Int>, longitude: ClosedRange<Int>) throws(ARINC424Error) -> ARINC424Coordinate? {
        if isBlank(latitude), isBlank(longitude) { return nil }
        let lat = try angle(field + " latitude", latitude, degreeDigits: 2, positive: 0x4E, negative: 0x53, limit: 90)
        let lon = try angle(field + " longitude", longitude, degreeDigits: 3, positive: 0x45, negative: 0x57, limit: 180)
        return ARINC424Coordinate(latitude: lat, longitude: lon)
    }

    public func requiredCoordinate(_ field: String, latitude: ClosedRange<Int>, longitude: ClosedRange<Int>) throws(ARINC424Error) -> ARINC424Coordinate {
        guard let value = try coordinate(field, latitude: latitude, longitude: longitude) else {
            throw error(field, latitude.lowerBound...longitude.upperBound, "the position is blank")
        }
        return value
    }

    private func angle(_ field: String, _ columns: ClosedRange<Int>, degreeDigits: Int, positive: UInt8, negative: UInt8, limit: Double) throws(ARINC424Error) -> Double {
        let hemisphere = byte(columns.lowerBound)
        guard hemisphere == positive || hemisphere == negative else { throw error(field, columns, "unknown hemisphere") }
        let start = columns.lowerBound + 1
        let degrees = try digits(field, columns, start, degreeDigits)
        let minutes = try digits(field, columns, start + degreeDigits, 2)
        let seconds = try digits(field, columns, start + degreeDigits + 2, 2)
        let hundredths = try digits(field, columns, start + degreeDigits + 4, 2)
        guard minutes < 60, seconds < 60 else { throw error(field, columns, "minutes or seconds are 60 or more") }
        let value = Double(degrees) + Double(minutes) / 60 + (Double(seconds) + Double(hundredths) / 100) / 3600
        guard value <= limit else { throw error(field, columns, "the angle is out of range") }
        return hemisphere == negative ? -value : value
    }

    private func digits(_ field: String, _ columns: ClosedRange<Int>, _ start: Int, _ count: Int) throws(ARINC424Error) -> Int {
        var value = 0
        for column in start..<(start + count) {
            let b = byte(column)
            guard b >= 0x30, b <= 0x39 else { throw error(field, columns, "a digit is expected in column \(column)") }
            value = value * 10 + Int(b - 0x30)
        }
        return value
    }

    // MARK: Aviation fields

    /// Magnetic variation or station declination `E0130` / `W0130` (tenths of a degree). East is positive.
    /// `T` means that the facility is aligned to true north: the value is 0.
    public func magneticVariation(_ field: String, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> Double? {
        if isBlank(columns) { return nil }
        let hemisphere = character(columns.lowerBound)
        let rest = (columns.lowerBound + 1)...columns.upperBound
        guard let value = Self.parseInteger(raw(rest)) else { throw error(field, columns, "not a magnetic variation") }
        switch hemisphere {
        case "E": return Double(value) / 10
        case "W": return -Double(value) / 10
        case "T": return 0
        default: throw error(field, columns, "unknown direction of magnetic variation")
        }
    }

    /// A course of 4 columns: tenths of a degree magnetic (`0438`), or whole degrees true (`044T`).
    public func bearing(_ field: String, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> ARINC424Bearing? {
        if isBlank(columns) { return nil }
        let isTrue = character(columns.upperBound) == "T"
        let numberColumns = isTrue ? columns.lowerBound...(columns.upperBound - 1) : columns
        guard let value = Self.parseInteger(raw(numberColumns)), value >= 0 else { throw error(field, columns, "not a course") }
        let degrees = isTrue ? Double(value) : Double(value) / 10
        guard degrees <= 360 else { throw error(field, columns, "the course is more than 360°") }
        return ARINC424Bearing(degrees: degrees, isTrue: isTrue)
    }

    /// Distance in tenths of a nautical mile (`0060`), or time in tenths of a minute (`T010`).
    public func distanceOrTime(_ field: String, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> ARINC424DistanceOrTime? {
        if isBlank(columns) { return nil }
        if character(columns.lowerBound) == "T" {
            let rest = (columns.lowerBound + 1)...columns.upperBound
            guard let value = Self.parseInteger(raw(rest)) else { throw error(field, columns, "not a time") }
            return .minutes(Double(value) / 10)
        }
        guard let value = Self.parseInteger(raw(columns)) else { throw error(field, columns, "not a distance") }
        return .nauticalMiles(Double(value) / 10)
    }

    /// An altitude of 5 columns: feet (`02000`, `-0028`) or a flight level (`FL180`). Blank is nil.
    public func altitude(_ field: String, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> Int? {
        let value = text(columns)
        if value.isEmpty { return nil }
        if value.hasPrefix("FL") {
            guard let level = Int(value.dropFirst(2)) else { throw error(field, columns, "not a flight level") }
            return level * 100
        }
        guard let feet = Self.parseInteger(value) else { throw error(field, columns, "not an altitude") }
        return feet
    }
}
