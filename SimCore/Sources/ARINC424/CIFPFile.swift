import Foundation

/// The header lines of a CIFP file (`HDR01` ... `HDR05`).
public struct CIFPHeader: Sendable, Equatable {
    /// File name in the header, for example `FAACIFP18`.
    public var fileName: String
    /// Number of data records in the file (without the header lines).
    public var recordCount: Int?
    /// AIRAC cycle identifier, for example `2611`.
    public var cycle: String
    /// Creation date as text, for example `07-OCT-2026`.
    public var creationDate: String
    /// Effective date from the text `EFFECTIVE 29 OCT 2026`, or nil when the header has no such text.
    public var effectiveDate: (year: Int, month: Int, day: Int)?
    /// All header lines.
    public var lines: [String]

    public static func == (lhs: CIFPHeader, rhs: CIFPHeader) -> Bool {
        lhs.fileName == rhs.fileName && lhs.recordCount == rhs.recordCount && lhs.cycle == rhs.cycle
            && lhs.creationDate == rhs.creationDate && lhs.lines == rhs.lines
            && lhs.effectiveDate.map { [$0.year, $0.month, $0.day] } == rhs.effectiveDate.map { [$0.year, $0.month, $0.day] }
    }

    /// Reads the header. `HDR01` must be the first line.
    public init(lines headerLines: [ARINC424Line]) throws(ARINC424Error) {
        guard let first = headerLines.first, first.raw(1...5) == "HDR01" else {
            throw ARINC424Error(line: headerLines.first?.number ?? 1, field: "header", columns: 1...5,
                                value: headerLines.first?.raw(1...5) ?? "", reason: "the file does not start with HDR01")
        }
        fileName = first.text(6...20)
        recordCount = try first.integer("record count", 29...35)
        cycle = first.text(36...39)
        creationDate = first.text(42...52)
        lines = headerLines.map { $0.text(1...132) }
        effectiveDate = lines.lazy.compactMap(Self.effectiveDate(in:)).first
        guard cycle.count == 4, cycle.allSatisfy(\.isNumber) else {
            throw first.error("cycle", 36...39, "not an AIRAC cycle")
        }
    }

    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// Finds `EFFECTIVE DD MMM YYYY` in a line.
    static func effectiveDate(in line: String) -> (year: Int, month: Int, day: Int)? {
        guard let range = line.range(of: "EFFECTIVE ") else { return nil }
        let words = line[range.upperBound...].split(separator: " ").prefix(3)
        guard words.count == 3, let day = Int(words[words.startIndex]),
              let month = months.firstIndex(of: String(words[words.startIndex + 1])),
              let year = Int(words[words.startIndex + 2])
        else { return nil }
        return (year, month + 1, day)
    }
}

/// Counts of the records of one type.
public struct RecordCount: Sendable, Equatable, Codable {
    /// Primary records that were read without errors.
    public var parsed = 0
    /// Primary records with an error.
    public var failed = 0
    /// Continuation records. This module does not read them.
    public var continuation = 0

    public init() {}
}

/// All records of a CIFP file that this module reads.
public struct CIFPContent: Sendable {
    public var header: CIFPHeader
    /// Number of lines in the file, with the header lines.
    public var lineCount = 0
    public var airports: [AirportRecord] = []
    public var runways: [RunwayRecord] = []
    public var localizers: [LocalizerRecord] = []
    public var terminalWaypoints: [WaypointRecord] = []
    public var terminalNDBs: [NDBRecord] = []
    public var enrouteWaypoints: [WaypointRecord] = []
    public var vhfNavaids: [VHFNavaidRecord] = []
    public var enrouteNDBs: [NDBRecord] = []
    public var airwayFixes: [AirwayFixRecord] = []
    public var procedureLegs: [ProcedureLegRecord] = []
    /// Counts by record type.
    public var counts: [RecordKind: RecordCount] = [:]
    /// Records of other types by code (section and subsection). They are skipped by design.
    public var skipped: [String: Int] = [:]
    /// Errors in records. A record with an error is not in the lists above.
    public var errors: [ARINC424Error] = []

    /// Number of data records (lines without the header lines).
    public var dataRecordCount: Int {
        lineCount - header.lines.count
    }
}

public enum CIFPFile {
    /// Splits the data into lines. A line with a wrong length is an error. Empty lines at the end are ignored.
    public static func lines(in data: Data) -> (lines: [ARINC424Line], errors: [ARINC424Error]) {
        var lines: [ARINC424Line] = []
        var errors: [ARINC424Error] = []
        lines.reserveCapacity(data.count / (ARINC424Line.length + 2))
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            let bytes = buffer.bindMemory(to: UInt8.self)
            var start = 0
            var number = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count, bytes[end] != 0x0A { end += 1 }
                number += 1
                let slice = UnsafeBufferPointer(rebasing: bytes[start..<end])
                if let line = ARINC424Line(number: number, bytes: slice) {
                    lines.append(line)
                } else if !(slice.isEmpty || (slice.count == 1 && slice[0] == 0x0D)) {
                    errors.append(ARINC424Error(line: number, field: "line", columns: 1...132,
                                                value: String(decoding: slice.prefix(20), as: UTF8.self),
                                                reason: "the line has \(slice.count) characters, 132 are expected"))
                }
                start = end + 1
            }
        }
        return (lines, errors)
    }

    /// Reads all records. An error in one record does not stop the read: the error goes to `errors`.
    /// Throws only when the header is not valid.
    public static func parse(_ data: Data) throws(ARINC424Error) -> CIFPContent {
        let (lines, lineErrors) = lines(in: data)
        let headerLines = Array(lines.prefix { $0.lineClass == .header })
        var content = CIFPContent(header: try CIFPHeader(lines: headerLines))
        content.lineCount = lines.count + lineErrors.count
        content.errors = lineErrors

        for line in lines.dropFirst(headerLines.count) {
            switch line.lineClass {
            case .header:
                content.errors.append(line.error("header", 1...5, "a header line after the data records"))
            case .other(let code):
                content.skipped[code, default: 0] += 1
            case .continuation(let kind):
                content.counts[kind, default: RecordCount()].continuation += 1
            case .primary(let kind):
                do {
                    try read(line, kind: kind, into: &content)
                    content.counts[kind, default: RecordCount()].parsed += 1
                } catch {
                    content.counts[kind, default: RecordCount()].failed += 1
                    content.errors.append(error)
                }
            }
        }
        return content
    }

    private static func read(_ line: ARINC424Line, kind: RecordKind, into content: inout CIFPContent) throws(ARINC424Error) {
        switch kind {
        case .airport: content.airports.append(try AirportRecord(line))
        case .runway: content.runways.append(try RunwayRecord(line))
        case .localizer: content.localizers.append(try LocalizerRecord(line))
        case .terminalWaypoint: content.terminalWaypoints.append(try WaypointRecord(line))
        case .terminalNDB: content.terminalNDBs.append(try NDBRecord(line))
        case .enrouteWaypoint: content.enrouteWaypoints.append(try WaypointRecord(line))
        case .vhfNavaid: content.vhfNavaids.append(try VHFNavaidRecord(line))
        case .enrouteNDB: content.enrouteNDBs.append(try NDBRecord(line))
        case .airway: content.airwayFixes.append(try AirwayFixRecord(line))
        case .sid, .star, .approach: content.procedureLegs.append(try ProcedureLegRecord(line))
        }
    }
}
