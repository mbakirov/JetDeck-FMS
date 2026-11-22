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
    #expect(report.passed, "\(report.routeMismatches.prefix(5)) \(report.valueMismatches.prefix(5))")
    #expect(report.airports == 6)
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
