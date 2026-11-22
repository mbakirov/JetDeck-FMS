import ARINC424
import Foundation
import Kernel
import NavDB
import Testing
@testable import NavDBBuilder

let sampleURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CIFP-sample-2611.txt")

/// A new empty directory for one test.
func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("navdb-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func buildSample(in directory: URL, name: String = "sample.sqlite") throws -> (path: String, report: BuildReport) {
    let path = directory.appendingPathComponent(name).path
    let report = try NavDBBuilder.build(cifp: Data(contentsOf: sampleURL), sourceFileName: "CIFP-sample-2611.txt", output: path)
    return (path, report)
}

@Test func reportOfTheSample() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (path, report) = try buildSample(in: directory)

    #expect(report.errorCount == 0)
    #expect(report.warnings.isEmpty)
    #expect(report.cycle.ident == "2611")
    #expect(report.cycle.effective.description == "2026-10-29")
    #expect(report.cycle.lastDay.description == "2026-11-25")
    #expect(report.source.sha256 == NavDBBuilder.sha256(try Data(contentsOf: sampleURL)))
    #expect(report.source.headerRecordCount == report.source.dataRecords)
    #expect(report.records["PA"]?.parsed == 10)
    #expect(report.records["PF"]?.continuation == 30)
    #expect(report.skippedByDesign["UC"] == 3)

    // Filter: the report shows the airports before and after the filter.
    #expect(report.airportFilter.before == 10)
    #expect(report.airportFilter.after == 6)
    #expect(report.airportFilter.rejected == ["notHardSurface": 2, "noILS": 1, "ilsRunwayTooShort": 1])
    #expect(report.airportFilter.rejectedShortRunway == ["KCRQ"])

    #expect(report.unresolvedReferences.count == 0)
    #expect(report.duplicateLegs.isEmpty)
    #expect(report.written["fix.airport"] == 6)
    #expect(report.written["procedure"] == report.written["procedure.APPROACH"]! + report.written["procedure.SID"]! + report.written["procedure.STAR"]!)
    #expect(report.pathTerminators.values.reduce(0, +) == report.written["procedure_leg"])
    #expect(report.approachTypes["I"]! > 0)
    #expect(report.databaseSizeBytes == (try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int))
}

@Test func sameInputGivesTheSameFile() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try buildSample(in: directory, name: "a.sqlite")
    let second = try buildSample(in: directory, name: "b.sqlite")
    #expect(first.report.databaseSHA256 == second.report.databaseSHA256)
    #expect(try Data(contentsOf: URL(fileURLWithPath: first.path)) == Data(contentsOf: URL(fileURLWithPath: second.path)))
    #expect(first.report == second.report)
}

@Test func outputIsReplacedOnlyAfterSuccess() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (path, _) = try buildSample(in: directory)
    let before = try Data(contentsOf: URL(fileURLWithPath: path))
    // A file without a header fails. The old database stays.
    #expect(throws: BuildError.self) {
        try NavDBBuilder.build(cifp: Data("NOT A CIFP FILE\r\n".utf8), sourceFileName: "x", output: path)
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
    #expect(!FileManager.default.fileExists(atPath: path + ".tmp"))
}

@Test func effectiveDateMustMatchTheCycle() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let text = try String(contentsOf: sampleURL, encoding: .utf8).replacingOccurrences(of: "EFFECTIVE 29 OCT 2026", with: "EFFECTIVE 30 OCT 2026")
    #expect {
        try NavDBBuilder.build(cifp: Data(text.utf8), sourceFileName: "x", output: directory.appendingPathComponent("x.sqlite").path)
    } throws: { error in
        guard case BuildError.cycle = error else { return false }
        return true
    }
}

@Test func filterRules() throws {
    let content = try CIFPFile.parse(Data(contentsOf: sampleURL))
    let filter = AirportFilter()
    func evaluate(_ ident: String, _ filter: AirportFilter = AirportFilter()) -> AirportFilter.Rejection? {
        let airport = content.airports.first { $0.ident == ident }!
        return filter.evaluate(airport, runways: content.runways.filter { $0.airport == ident },
                               localizers: content.localizers.filter { $0.airport == ident })
    }
    #expect(filter.minimumRunwayFt == 5000)
    for ident in ["KJFK", "KMRY", "KACK", "TJSJ", "PANC", "KBTV"] {
        #expect(evaluate(ident) == nil, "\(ident)")
    }
    #expect(evaluate("KCRQ") == .ilsRunwayTooShort)
    #expect(evaluate("KASE") == .noILS)
    #expect(evaluate("13FD") == .notHardSurface)
    #expect(evaluate("5KE") == .notHardSurface)
    // KCRQ runway 24 is 4897 ft long.
    #expect(evaluate("KCRQ", AirportFilter(minimumRunwayFt: 4800)) == nil)
}

@Test func approachRunwayAndRouteRoles() {
    #expect(Plan.approachRunway("I04L") == "RW04L")
    #expect(Plan.approachRunway("R13LY") == "RW13L")
    #expect(Plan.approachRunway("L22") == "RW22")
    #expect(Plan.approachRunway("VDM-A") == nil)
    #expect(Plan.role(.sid, routeType: "4") == .runwayTransition)
    #expect(Plan.role(.sid, routeType: "2") == .common)
    #expect(Plan.role(.sid, routeType: "6") == .enrouteTransition)
    #expect(Plan.role(.star, routeType: "1") == .enrouteTransition)
    #expect(Plan.role(.star, routeType: "5") == .common)
    #expect(Plan.role(.star, routeType: "6") == .runwayTransition)
    #expect(Plan.role(.approach, routeType: "A") == .approachTransition)
    #expect(Plan.role(.approach, routeType: "I") == .final)
}

@Test func navaidTypes() {
    #expect(FixCatalog.vhfType("VDHW ") == .vorDme)
    #expect(FixCatalog.vhfType("VTHW ") == .vortac)
    #expect(FixCatalog.vhfType("V HW ") == .vor)
    #expect(FixCatalog.vhfType(" DHW ") == .dme)
    #expect(FixCatalog.vhfType(" THW ") == .tacan)
    #expect(FixCatalog.vhfType(" ITW ") == .ilsDme)
    #expect(FixCatalog.ndbType("HO W ") == .locator)
    #expect(FixCatalog.ndbType("H HW ") == .ndb)
}

/// Acceptance criterion: each ILS approach, STAR and SID of a kept airport is in the database with all legs.
/// The same check runs on the full file with `make navdb-verify`.
@Test func verifierPassesOnTheSample() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (path, _) = try buildSample(in: directory)
    let reader = try NavDatabaseReader(path: path)
    let report = try NavDBVerifier.verify(cifp: Data(contentsOf: sampleURL), database: reader, sampleSize: 20)
    #expect(report.passed, "\(report.airportMismatches) \(report.routeMismatches.prefix(5)) \(report.valueMismatches.prefix(5))")
    #expect(report.airports == 6)
    #expect(report.sourceAirports == 6)
    #expect(report.airportMismatches.isEmpty)
    #expect(report.sample.count == 6)
    #expect(report.sourceILSApproaches > 0)
    #expect(report.sourceProcedures.keys.sorted() == ["APPROACH", "SID", "STAR"])
}

@Test func verifierFindsAChangedDatabase() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (path, _) = try buildSample(in: directory)
    let db = try SQLiteDatabase(path: path, mode: .readWriteCreate)
    try db.execute("""
        UPDATE ils SET frequency_mhz = 999 WHERE fix_id = (SELECT id FROM fix WHERE ident = 'IHIQ');
        DELETE FROM procedure_leg WHERE seq = 30 AND transition_id IN
            (SELECT t.id FROM procedure_transition t JOIN procedure p ON p.id = t.procedure_id WHERE p.airport = 'KJFK' AND p.ident = 'I04L');
        """)
    let reader = try NavDatabaseReader(path: path)
    let report = try NavDBVerifier.verify(cifp: Data(contentsOf: sampleURL), database: reader)
    #expect(!report.passed)
    #expect(report.routeMismatches == ["KJFK|APPROACH|I04L|I|: source 6 legs, database 5 legs"])
    #expect(report.valueMismatches.contains { $0.contains("IHIQ frequency") })
}

@Test func verifierFindsAMissingAirport() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (path, _) = try buildSample(in: directory)
    // The converter "lost" KACK with all its procedures.
    let db = try SQLiteDatabase(path: path, mode: .readWriteCreate)
    try db.execute("""
        DELETE FROM procedure_leg WHERE transition_id IN (SELECT t.id FROM procedure_transition t
            JOIN procedure p ON p.id = t.procedure_id WHERE p.airport = 'KACK');
        DELETE FROM procedure_transition WHERE procedure_id IN (SELECT id FROM procedure WHERE airport = 'KACK');
        DELETE FROM procedure WHERE airport = 'KACK';
        DELETE FROM airport WHERE fix_id IN (SELECT id FROM fix WHERE airport = 'KACK');
        DELETE FROM fix WHERE airport = 'KACK';
        """)
    let report = try NavDBVerifier.verify(cifp: Data(contentsOf: sampleURL), database: try NavDatabaseReader(path: path))
    #expect(!report.passed)
    #expect(report.airportMismatches == ["KACK: passes the filter, not in the database"])
    #expect(report.airports == 5)
    #expect(report.sourceAirports == 6)
}

@Test func benchMeasuresTheQuery() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (path, _) = try buildSample(in: directory)
    let report = try NavDBBench.run(try NavDatabaseReader(path: path), radiusNM: 320, repeatCount: 3)
    #expect(report.centers.count == NavDBBench.defaultCenters.count)
    #expect(report.centers.first { $0.name == "KJFK" }!.fixes > 0)
    #expect(report.p99Microseconds >= report.p50Microseconds)
}

@Test func sampleOfTheSample() throws {
    let data = try CIFPSampler.extract(from: Data(contentsOf: sampleURL), airports: ["KMRY"])
    let content = try CIFPFile.parse(data)
    #expect(content.errors.isEmpty)
    #expect(content.airports.map(\.ident) == ["KMRY"])
    #expect(content.header.recordCount == content.dataRecordCount)
    #expect(content.procedureLegs.allSatisfy { $0.airport == "KMRY" })
}

// MARK: Airway segments

/// An airway record made from a real one (T461 in FAACIFP18) with other area, route, sequence, fix and description.
func airwayRecord(_ area: String, _ route: String, _ sequence: Int, _ fix: String, _ description: String = "E   ",
                  line: Int) -> AirwayFixRecord {
    var bytes = Array("SUSAER       T461        0110BELTTK6EA0E    RL                        326200320546 01800     06000                         629302512".utf8)
    func put(_ text: String, _ columns: ClosedRange<Int>) {
        let padded = text.padding(toLength: columns.count, withPad: " ", startingAt: 0)
        bytes.replaceSubrange((columns.lowerBound - 1)..<columns.upperBound, with: Array(padded.utf8))
    }
    put(area, 2...4)
    put(route, 14...18)
    put(String(format: "%04d", sequence), 26...29)
    put(fix, 30...34)
    put(description, 40...43)
    return try! AirwayFixRecord(ARINC424Line(number: line, bytes: bytes)!)
}

func segments(_ records: [AirwayFixRecord]) -> [String] {
    Plan.airwaySegments(records).map { "\($0.1) \($0.0.sequence) \($0.0.fix.ident) \($0.0.area)" }
}

@Test func airwaySplitBetweenAreasIsOneSegment() {
    // A342 in FAACIFP18: PINSO is the boundary fix in PAC and in CAN with the same sequence number.
    let records = [
        airwayRecord("CAN", "A342", 120, "PINSO", line: 1), airwayRecord("CAN", "A342", 130, "AMOND", line: 2),
        airwayRecord("CAN", "A342", 140, "CDB", "VE  ", line: 3),
        airwayRecord("PAC", "A342", 100, "NUZAN", line: 4), airwayRecord("PAC", "A342", 110, "OPAKE", line: 5),
        airwayRecord("PAC", "A342", 120, "PINSO", "EE  ", line: 6),
    ]
    #expect(segments(records) == ["1 100 NUZAN PAC", "1 110 OPAKE PAC", "1 120 PINSO CAN", "1 130 AMOND CAN", "1 140 CDB CAN"])
}

@Test func airwayThatLeavesAndEntersAnAreaIsOneSegment() {
    // M576 in FAACIFP18: USA ANNER (end flag) and PJM, LAM ANNER-PORQE-DANDE-PJM between them.
    let records = [
        airwayRecord("LAM", "M576", 130, "ANNER", line: 1), airwayRecord("LAM", "M576", 140, "PORQE", line: 2),
        airwayRecord("LAM", "M576", 150, "DANDE", line: 3), airwayRecord("LAM", "M576", 160, "PJM", "VE  ", line: 4),
        airwayRecord("USA", "M576", 100, "MILOK", line: 5), airwayRecord("USA", "M576", 130, "ANNER", "EE  ", line: 6),
        airwayRecord("USA", "M576", 160, "PJM", "V   ", line: 7), airwayRecord("USA", "M576", 170, "MNOLO", "EE  ", line: 8),
    ]
    #expect(segments(records) == ["1 100 MILOK USA", "1 130 ANNER LAM", "1 140 PORQE LAM", "1 150 DANDE LAM",
                                  "1 160 PJM USA", "1 170 MNOLO USA"])
}

@Test func airwaysWithTheSameNameAndBreaksAreSegments() {
    // V1 in FAACIFP18: USA 100-550 with a break after ISO (320), and another V1 in PAC from 5100.
    let records = [
        airwayRecord("PAC", "V1", 5100, "KOA", line: 1), airwayRecord("PAC", "V1", 5110, "OGG", "VE  ", line: 2),
        airwayRecord("USA", "V1", 100, "CRG", line: 3), airwayRecord("USA", "V1", 320, "ISO", "VE  ", line: 4),
        airwayRecord("USA", "V1", 330, "ATR", line: 5), airwayRecord("USA", "V1", 550, "BOS", "VE  ", line: 6),
    ]
    #expect(segments(records) == ["1 100 CRG USA", "1 320 ISO USA", "2 330 ATR USA", "2 550 BOS USA",
                                  "3 5100 KOA PAC", "3 5110 OGG PAC"])
    // J501: parts in USA and CAN without a shared fix (the part in Canada is not in the data).
    let j501 = [
        airwayRecord("CAN", "J501", 230, "EEVER", line: 1), airwayRecord("CAN", "J501", 350, "BET", "VE  ", line: 2),
        airwayRecord("USA", "J501", 100, "RZS", line: 3), airwayRecord("USA", "J501", 200, "CYVIC", "EE  ", line: 4),
    ]
    #expect(segments(j501) == ["1 100 RZS USA", "1 200 CYVIC USA", "2 230 EEVER CAN", "2 350 BET CAN"])
}

// MARK: References and runways

/// The sample with some lines changed.
func buildChangedSample(in directory: URL, _ changes: [(String, String)]) throws -> (path: String, report: BuildReport) {
    var text = try String(contentsOf: sampleURL, encoding: .utf8)
    for (old, new) in changes {
        precondition(text.contains(old), "not in the sample: \(old)")
        text = text.replacingOccurrences(of: old, with: new)
    }
    let path = directory.appendingPathComponent("changed.sqlite").path
    return (path, try NavDBBuilder.build(cifp: Data(text.utf8), sourceFileName: "changed", output: path))
}

@Test func referenceToARejectedAirportIsNotWritten() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // The center fix of a KJFK leg points at KASE (an airport without ILS), as an FAA typing error would.
    let leg = "2238006504400060PI  H 0150001500            JFK   K6D 0 NS"
    let (path, report) = try buildChangedSample(in: directory, [(leg, leg.replacingOccurrences(of: "JFK   K6D ", with: "KASE  K2PA"))])
    #expect(report.written["fix.airport"] == 6)
    #expect(report.unresolvedReferences.count == 1)
    #expect(report.unresolvedReferences.samples.first?.hasSuffix("the airport is not in the database") == true)
    let reader = try NavDatabaseReader(path: path)
    #expect(try reader.airport("KASE") == nil)
    let verify = try NavDBVerifier.verify(cifp: Data(contentsOf: sampleURL), database: reader)
    #expect(verify.airportMismatches.isEmpty)
}

@Test func secondLocalizerOfARunwayIsReadable() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // RW04L of KJFK with a second localizer IXYZ, category 1, in columns 91-95.
    let runway = "SUSAP KJFKK6GRW04L   0120790440 N40372318W073470505         -0028300012046057200IIHIQ1    "
    let (path, _) = try buildChangedSample(in: directory, [(runway + "     ", runway + "IXYZ1")])
    let rw04L = try NavDatabaseReader(path: path).runways(airport: "KJFK").first { $0.ident == "RW04L" }
    #expect(rw04L?.localizerIdent == "IHIQ")
    #expect(rw04L?.secondLocalizerIdent == "IXYZ")
    #expect(rw04L?.secondLocalizerCategory == "1")
}
