import ARINC424
import Foundation
import SimCoreContract

/// The report of one conversion. It is written as JSON next to the database.
public struct BuildReport: Sendable, Codable, Equatable {
    public struct Source: Sendable, Codable, Equatable {
        public var file: String
        public var sha256: String
        public var sizeBytes: Int
        /// Lines in the file, with the header lines.
        public var lines: Int
        /// Number of data records stated in HDR01.
        public var headerRecordCount: Int?
        /// Number of data records in the file.
        public var dataRecords: Int
        public var created: String
    }

    public struct Cycle: Sendable, Codable, Equatable {
        public var ident: String
        public var effective: CalendarDate
        public var lastDay: CalendarDate
    }

    public struct Filter: Sendable, Codable, Equatable {
        public var minimumRunwayFt: Int
        /// Airports in the source file.
        public var before: Int
        /// Airports in the database.
        public var after: Int
        public var rejected: [String: Int]
        /// Airports with an ILS on a runway that is shorter than the minimum. The list helps to check the filter.
        public var rejectedShortRunway: [String]
    }

    public struct Unresolved: Sendable, Codable, Equatable {
        public var count: Int
        /// Count by the code of the referenced record.
        public var byCode: [String: Int]
        /// The first references, for example `KJFK I04L 020 fix ABCDE K6 PC`.
        public var samples: [String]
    }

    public var builderVersion: Int
    public var schemaVersion: Int
    public var source: Source
    public var cycle: Cycle
    /// Records of the types that the converter reads, by ARINC 424 code.
    public var records: [String: RecordCount]
    /// Records of other types by code. The converter skips them by design (airspace, MSA, heliports, path points).
    public var skippedByDesign: [String: Int]
    /// Records that are not read because of an error.
    public var errorCount: Int
    public var errors: [String]
    public var warnings: [String]
    public var airportFilter: Filter
    /// Rows in each table of the database.
    public var written: [String: Int]
    public var unresolvedReferences: Unresolved
    /// Legs with a sequence number that is already in the route. They are not written.
    public var duplicateLegs: [String]
    /// Number of legs of each path and terminator in the written procedures. E07 uses it to select the leg types.
    public var pathTerminators: [String: Int]
    /// Number of approaches of each route type of the final approach.
    public var approachTypes: [String: Int]
    public var databaseSizeBytes: Int
    public var databaseSHA256: String

    /// Total of all skipped records: types skipped by design and continuation records.
    public var skippedTotal: Int {
        skippedByDesign.values.reduce(0, +) + records.values.reduce(0) { $0 + $1.continuation }
    }

    /// A short text for the terminal.
    public var summary: String {
        var lines: [String] = []
        lines.append("AIRAC \(cycle.ident) (\(cycle.effective) – \(cycle.lastDay)), source \(source.file), \(source.lines) lines")
        lines.append("records read:")
        for code in records.keys.sorted() {
            let c = records[code]!
            lines.append("  \(code.padding(toLength: 3, withPad: " ", startingAt: 0)) parsed \(c.parsed), errors \(c.failed), continuation \(c.continuation)")
        }
        let skipped = skippedByDesign.keys.sorted().map { "\($0) \(skippedByDesign[$0]!)" }.joined(separator: ", ")
        lines.append("skipped by design: \(skipped)")
        lines.append("errors: \(errorCount), warnings: \(warnings.count), unresolved references: \(unresolvedReferences.count), duplicate legs: \(duplicateLegs.count)")
        let rejected = airportFilter.rejected.keys.sorted().map { "\($0) \(airportFilter.rejected[$0]!)" }.joined(separator: ", ")
        lines.append("airports: \(airportFilter.before) before filter, \(airportFilter.after) after filter (\(rejected))")
        let written = self.written.keys.sorted().map { "\($0) \(self.written[$0]!)" }.joined(separator: ", ")
        lines.append("written: \(written)")
        lines.append("database: \(databaseSizeBytes) bytes, SHA-256 \(databaseSHA256)")
        return lines.joined(separator: "\n")
    }
}
