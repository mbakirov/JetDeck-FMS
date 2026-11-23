import Foundation
import Kernel
import NavDBBuilder
import SimCoreContract
import Testing
@testable import NavDB

let sampleURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CIFP-sample-2611.txt")

/// The database of the test sample. It is made once for all tests of this file.
let sampleDatabasePath: String = {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("navdb-reader-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("sample.sqlite").path
    _ = try! NavDBBuilder.build(cifp: Data(contentsOf: sampleURL), sourceFileName: "CIFP-sample-2611.txt", output: path)
    return path
}()

func sampleReader() throws -> NavDatabaseReader {
    try NavDatabaseReader(path: sampleDatabasePath)
}

/// A copy of the sample database that a test can change.
func copyOfSample() throws -> String {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("navdb-copy-\(UUID().uuidString).sqlite").path
    try FileManager.default.copyItem(atPath: sampleDatabasePath, toPath: path)
    return path
}

@Test func identityAndCycleForTheMCDU() throws {
    let reader = try sampleReader()
    let identity = try #require(reader.identity)
    #expect(identity.cycle.ident == "2611")
    #expect(identity.schemaVersion == NavDBSchema.version)
    #expect(identity.builderVersion == NavDBBuilder.version)
    #expect(identity.sourceSHA256 == NavDBBuilder.sha256(try Data(contentsOf: sampleURL)))
    // A/C STATUS page: number and dates of the cycle.
    #expect(reader.cycle?.effective.description == "2026-10-29")
    #expect(reader.cycle?.lastDay.description == "2026-11-25")
    try reader.checkIntegrity()
}

@Test func airportByIdent() throws {
    let reader = try sampleReader()
    let jfk = try #require(try reader.airport("KJFK"))
    #expect(jfk.name == "JOHN F KENNEDY INTL")
    #expect(jfk.iata == "JFK")
    #expect(jfk.fix.kind == .airport)
    #expect(jfk.fix.region == "K6")
    #expect(abs(jfk.position.latDeg - 40.63992778) < 1e-6)
    #expect(jfk.elevationFt == 13)
    #expect(jfk.transitionAltitudeFt == 18000)
    #expect(jfk.magneticVariationDeg == -13)
    // Airports that the filter rejected are not in the database.
    #expect(try reader.airport("KASE") == nil)
    #expect(try reader.airport("KCRQ") == nil)
    #expect(try reader.airport("XXXX") == nil)
}

@Test func runwaysAndLocalizers() throws {
    let reader = try sampleReader()
    let runways = try reader.runways(airport: "KJFK")
    #expect(runways.map(\.ident) == ["RW04L", "RW04R", "RW13L", "RW13R", "RW22L", "RW22R", "RW31L", "RW31R"])
    let rw04L = runways[0]
    #expect(rw04L.lengthFt == 12079)
    #expect(rw04L.bearing == NavCourse(degrees: 44, isTrue: false))
    #expect(rw04L.localizerIdent == "IHIQ")
    #expect(rw04L.secondLocalizerIdent == nil)
    #expect(rw04L.fix.airport == "KJFK")

    let localizers = try reader.localizers(airport: "KJFK")
    #expect(localizers.map(\.ident) == ["IHIQ", "IIWY", "IJFK", "IJOC", "IMOH", "IRTH", "ITLK"])
    let ihiq = localizers[0]
    #expect(ihiq.frequencyMHz == 110.9)
    #expect(ihiq.runway == "RW04L")
    #expect(ihiq.course == NavCourse(degrees: 43.8, isTrue: false))
    #expect(ihiq.glideSlopeAngleDeg == 3)
    #expect(ihiq.isILSWithGlideSlope)
    #expect(ihiq.glideSlopePosition != nil)
}

@Test func fixesNavaidsAndWaypointsByIdent() throws {
    let reader = try sampleReader()
    let navaids = try reader.navaids(ident: "JFK")
    #expect(navaids.count == 1)
    #expect(navaids[0].type == .vorDme)
    #expect(navaids[0].frequency == 115.9)
    #expect(navaids[0].name == "KENNEDY")

    let fixes = try reader.fixes(ident: "JFK")
    #expect(fixes.map(\.kind) == [.vhfNavaid])

    let waypoints = try reader.waypoints(ident: "AROKE")
    #expect(waypoints.count == 1)
    #expect(waypoints[0].fix.airport == "KJFK")
    #expect(try reader.fixes(ident: "NOSUCH").isEmpty)
}

@Test func proceduresOfAnAirport() throws {
    let reader = try sampleReader()
    let all = try reader.procedures(airport: "KJFK", kind: nil)
    #expect(all.map(\.kind.rawValue) == all.map(\.kind.rawValue).sorted())
    let sids = try reader.procedures(airport: "KJFK", kind: .sid)
    #expect(sids.map(\.ident) == ["DEEZZ6", "SKORR6"])
    #expect(sids.allSatisfy { $0.approachType == nil && $0.runway == nil })
    let stars = try reader.procedures(airport: "KJFK", kind: .star)
    #expect(stars.map(\.ident) == ["CAMRN5", "PARCH4", "PAWLN1", "PUCKY1"])
    let approaches = try reader.procedures(airport: "KJFK", kind: .approach)
    let i04L = try #require(approaches.first { $0.ident == "I04L" })
    #expect(i04L.approachType == "I")
    #expect(i04L.runway == "RW04L")
    #expect(i04L.transitions.map(\.role) == [.final])
    // `R027` is not an approach to a runway 02.
    #expect(approaches.first { $0.ident == "R027" }?.runway == nil)
    #expect(all.count == sids.count + stars.count + approaches.count)
}

@Test func legsOfTheILS04L() throws {
    let reader = try sampleReader()
    let i04L = try #require(try reader.procedures(airport: "KJFK", kind: .approach).first { $0.ident == "I04L" })
    let legs = try reader.legs(transitionID: i04L.transitions[0].id)
    #expect(legs.map(\.sequence) == [10, 20, 30, 40, 50, 60])
    #expect(legs.map(\.pathTerminator) == ["IF", "CF", "CF", "CA", "CF", "HM"])
    #expect(legs.map { $0.fix?.ident } == ["AROKE", "KRSTL", "RW04L", nil, "DUFFY", "DUFFY"])
    // All references are resolved to fixes of the database.
    #expect(legs.compactMap(\.fix).allSatisfy { $0.fix != nil })
    #expect(legs[2].fix?.fix?.kind == .runway)
    #expect(legs[1].recommendedNavaid?.fix?.kind == .localizer)
    #expect(legs[1].centerFix?.fix?.ident == "JFK")
    #expect(legs[1].altitudeDescription == "H")
    #expect(legs[1].altitude1Ft == 1500)
    #expect(legs[1].distanceNM == 6.0)
    #expect(legs[2].verticalAngleDeg == -3)
    #expect(legs[2].isFlyOver)
    #expect(legs[3].isFirstMissedApproachLeg)
    #expect(legs[3].course == NavCourse(degrees: 43.8, isTrue: false))
    #expect(legs[5].holdTimeMinutes == 1.0)
    #expect(legs[5].turnDirection == "L")
}

@Test func transitionsOfAStar() throws {
    let reader = try sampleReader()
    let stars = try reader.procedures(airport: "KJFK", kind: .star)
    // CAMRN5 has only the common route (route type 2, transition ALL). PARCH4 has RNAV en route transitions (type 4).
    let camrn = try #require(stars.first { $0.ident == "CAMRN5" })
    #expect(camrn.transitions.map(\.role) == [.common])
    #expect(camrn.transitions.map(\.ident) == ["ALL"])
    let parch = try #require(stars.first { $0.ident == "PARCH4" })
    #expect(parch.transitions.contains { $0.role == .enrouteTransition && $0.routeType == "4" })
    for transition in camrn.transitions + parch.transitions {
        let legs = try reader.legs(transitionID: transition.id)
        #expect(!legs.isEmpty)
        #expect(legs.map(\.sequence) == legs.map(\.sequence).sorted())
    }
}

@Test func airwayInSequence() throws {
    let reader = try sampleReader()
    let route = try reader.query { db throws(SQLiteError) in
        try db.rows("SELECT route FROM airway_fix ORDER BY id LIMIT 1") { $0.text(0) }.first!
    }
    let fixes = try reader.airway(route)
    #expect(fixes.count >= 2)
    for segment in Set(fixes.map(\.segment)) {
        let sequences = fixes.filter { $0.segment == segment }.map(\.sequence)
        #expect(sequences == sequences.sorted())
    }
    #expect(fixes.allSatisfy { $0.fix.fix != nil })
    #expect(try reader.airway("NOSUCH").isEmpty)
}

@Test func airwaysWithTheSameNameInTwoAreas() throws {
    // V440 is in the USA area (sequence 100-150) and in the CAN area (Alaska, 5100-5460). They share no fix,
    // so they are two segments.
    let fixes = try sampleReader().airway("V440")
    #expect(fixes.map(\.segment) == fixes.map(\.segment).sorted())
    #expect(Set(fixes.filter { $0.segment == 1 }.map(\.area)) == ["USA"])
    #expect(Set(fixes.filter { $0.segment == 2 }.map(\.area)) == ["CAN"])
    for segment in Set(fixes.map(\.segment)) {
        let sequences = fixes.filter { $0.segment == segment }.map(\.sequence)
        #expect(sequences == sequences.sorted())
        #expect(Set(sequences).count == sequences.count)
    }
}

@Test func fixesNearAPointForTheND() throws {
    let reader = try sampleReader()
    let jfk = try #require(try reader.airport("KJFK"))
    let all = try reader.fixes(near: jfk.position, radiusNM: 320, kinds: [])
    #expect(!all.isEmpty)
    #expect(all.first?.ident == "KJFK" || all.first?.airport == "KJFK")
    let distances = all.map { jfk.position.distanceNM(to: $0.position) }
    #expect(distances == distances.sorted())
    #expect(distances.allSatisfy { $0 <= 320 })
    // KBTV and KACK are within 320 NM of KJFK. TJSJ is not.
    let airports = try reader.fixes(near: jfk.position, radiusNM: 320, kinds: [.airport]).map(\.ident)
    #expect(Set(airports) == ["KJFK", "KACK", "KBTV"])
    let navaids = try reader.fixes(near: jfk.position, radiusNM: 320, kinds: [.vhfNavaid, .ndb])
    #expect(navaids.allSatisfy { $0.kind == .vhfNavaid || $0.kind == .ndb })
    #expect(try reader.fixes(near: jfk.position, radiusNM: 10, kinds: [.airport]).map(\.ident) == ["KJFK"])
    // The same call gives the same result.
    #expect(try reader.fixes(near: jfk.position, radiusNM: 320, kinds: []) == all)
}

@Test func readerIsSafeFromManyThreads() async throws {
    let reader = try sampleReader()
    let expected = try reader.procedures(airport: "KJFK", kind: nil)
    try await withThrowingTaskGroup(of: [NavProcedure].self) { group in
        for _ in 0..<8 {
            group.addTask { try reader.procedures(airport: "KJFK", kind: nil) }
        }
        for try await result in group {
            #expect(result == expected)
        }
    }
}

@Test func otherSchemaVersionIsRejected() throws {
    let path = try copyOfSample()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try SQLiteDatabase(path: path, mode: .readWriteCreate).execute("PRAGMA user_version = 99")
    #expect(throws: NavDataError.schemaMismatch(found: 99, expected: NavDBSchema.version)) {
        try NavDatabaseReader(path: path)
    }
}

@Test func fileThatIsNotADatabaseIsRejected() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("navdb-garbage-\(UUID().uuidString).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    try Data(repeating: 0x41, count: 8192).write(to: URL(fileURLWithPath: path))
    #expect(throws: NavDataError.self) { try NavDatabaseReader(path: path) }
    #expect(throws: NavDataError.self) { try NavDatabaseReader(path: path + ".missing") }
}

@Test func emptyMetaIsRejected() throws {
    let path = try copyOfSample()
    defer { try? FileManager.default.removeItem(atPath: path) }
    try SQLiteDatabase(path: path, mode: .readWriteCreate).execute("DELETE FROM meta WHERE key = 'cycle'")
    #expect(throws: NavDataError.invalid("no valid AIRAC cycle in table meta")) { try NavDatabaseReader(path: path) }
}
