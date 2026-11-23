import Foundation
import Testing
@testable import ARINC424

/// The test sample: a part of FAACIFP18 cycle 2611. `navdb-cli extract-sample` made it.
/// Airports: KJFK, KMRY, KACK, TJSJ, PANC, KBTV (pass the filter), KCRQ (ILS runway shorter than 5000 ft),
/// KASE (no ILS), 13FD (soft surface, a runway without bearing), 5KE (water runways).
let sampleURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CIFP-sample-2611.txt")

@Test func headerOfTheSample() throws {
    let content = try CIFPFile.parse(Data(contentsOf: sampleURL))
    let header = content.header
    #expect(header.fileName == "FAACIFP18")
    #expect(header.cycle == "2611")
    #expect(header.creationDate == "07-OCT-2026")
    #expect(header.effectiveDate?.year == 2026)
    #expect(header.effectiveDate?.month == 10)
    #expect(header.effectiveDate?.day == 29)
    #expect(header.lines.count == 5)
    #expect(header.recordCount == content.dataRecordCount)
}

@Test func sampleIsReadWithoutErrors() throws {
    let content = try CIFPFile.parse(Data(contentsOf: sampleURL))
    #expect(content.errors.isEmpty, "\(content.errors.prefix(3))")
    #expect(content.airports.map(\.ident).sorted() == ["13FD", "5KE", "KACK", "KASE", "KBTV", "KCRQ", "KJFK", "KMRY", "PANC", "TJSJ"])
    #expect(content.counts[.airport]?.parsed == 10)
    #expect(content.counts[.approach]?.continuation == 30)
    #expect(content.runways.count == content.counts[.runway]?.parsed)
    #expect(content.procedureLegs.count == (content.counts[.sid]?.parsed ?? 0) + (content.counts[.star]?.parsed ?? 0)
        + (content.counts[.approach]?.parsed ?? 0))
    // Records of types that are skipped by design.
    #expect(content.skipped["UC"] == 3)
    #expect(content.skipped["PS"] == 40)
    // Each line is counted once.
    let counted = content.counts.values.reduce(0) { $0 + $1.parsed + $1.failed + $1.continuation }
        + content.skipped.values.reduce(0, +)
    #expect(counted == content.dataRecordCount)
}

@Test func badLinesAreReportedAndTheReadContinues() throws {
    var text = try String(contentsOf: sampleURL, encoding: .utf8)
    // A short line and a bad latitude in an airport record.
    text += "SHORT LINE\r\n"
    text += Lines.airportJFK.replacingOccurrences(of: "N40382374", with: "N4038Z374") + "\r\n"
    let content = try CIFPFile.parse(Data(text.utf8))
    #expect(content.errors.count == 2)
    #expect(content.errors.contains { $0.reason.contains("132 are expected") })
    #expect(content.errors.contains { $0.columns == 33...41 })
    #expect(content.counts[.airport]?.parsed == 10)
    #expect(content.counts[.airport]?.failed == 1)
}

@Test func fileWithoutHeaderIsRejected() {
    #expect(throws: ARINC424Error.self) {
        try CIFPFile.parse(Data((Lines.airportJFK + "\r\n").utf8))
    }
}

@Test func effectiveDateIsReadFromTheHeaderText() {
    let date = CIFPHeader.effectiveDate(in: "CODED INSTRUMENT FLIGHT PROCEDURES VOLUME 2611  EFFECTIVE 29 OCT 2026")
    #expect(date?.year == 2026 && date?.month == 10 && date?.day == 29)
    #expect(CIFPHeader.effectiveDate(in: "NO DATE HERE") == nil)
    #expect(CIFPHeader.effectiveDate(in: "EFFECTIVE 29 XYZ 2026") == nil)
}
