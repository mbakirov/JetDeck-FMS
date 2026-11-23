import Foundation
import Kernel
import NavDB
import SimCoreContract

/// The result of `NavDBVerifier.verify`.
public struct VerifyReport: Sendable, Codable, Equatable {
    public struct AirportCheck: Sendable, Codable, Equatable {
        public var airport: String
        public var procedures: Int
        public var runwaysChecked: Int
        public var localizersChecked: Int
    }

    public var cycle: String
    /// Airports in the database.
    public var airports: Int
    /// Airports that pass the filter when the check applies it to the source file.
    public var sourceAirports: Int
    /// Airports that are in the database but not expected, or expected but not in the database.
    public var airportMismatches: [String]
    /// Procedures of these airports in the source file, by kind.
    public var sourceProcedures: [String: Int]
    /// Procedures in the database, by kind.
    public var databaseProcedures: [String: Int]
    /// ILS approaches (route type I) in the source file and in the database.
    public var sourceILSApproaches: Int
    public var databaseILSApproaches: Int
    public var sourceLegs: Int
    public var databaseLegs: Int
    /// Procedure routes of the source file that are not in the database, or that have another number of legs.
    public var routeMismatches: [String]
    /// The airports of the sample check of runways and ILS.
    public var sample: [AirportCheck]
    /// Values of the sample that are not equal to the source file.
    public var valueMismatches: [String]

    public var passed: Bool {
        airportMismatches.isEmpty && routeMismatches.isEmpty && valueMismatches.isEmpty && sourceLegs == databaseLegs
            && sourceProcedures == databaseProcedures && sourceILSApproaches == databaseILSApproaches
    }

    public var summary: String {
        var lines = ["AIRAC \(cycle): \(airports) airports in the database, \(sourceAirports) expected by the filter",
                     "airport mismatches: \(airportMismatches.count)"]
        for kind in sourceProcedures.keys.sorted() {
            lines.append("  \(kind): source \(sourceProcedures[kind]!), database \(databaseProcedures[kind] ?? 0)")
        }
        lines.append("  ILS approaches: source \(sourceILSApproaches), database \(databaseILSApproaches)")
        lines.append("  legs: source \(sourceLegs), database \(databaseLegs)")
        lines.append("route mismatches: \(routeMismatches.count)")
        let checked = sample.map { "\($0.airport) (\($0.procedures) PROC, \($0.runwaysChecked) RWY, \($0.localizersChecked) LOC)" }
            .joined(separator: ", ")
        lines.append("sample of \(sample.count) airports: \(checked)")
        lines.append("value mismatches: \(valueMismatches.count)")
        lines.append(passed ? "PASSED" : "FAILED")
        return lines.joined(separator: "\n")
    }
}

/// Checks a database against its source file.
///
/// The check reads the source file with its own code (fixed columns of ARINC 424-18), not with the parser
/// of the converter. Thus an error in the parser is not hidden by the same error in the check.
/// The database is read through `NavDatabaseReader`, as the core reads it.
/// The list of airports also comes from the source file (the filter is applied again by this code),
/// so an airport that the converter lost is found.
public enum NavDBVerifier {
    public static func verify(cifp data: Data, database: NavDatabaseReader, sampleSize: Int = 20,
                              minimumRunwayFt: Int = AirportFilter.standard.minimumRunwayFt) throws(NavDataError) -> VerifyReport {
        let lines = rawLines(data)
        let databaseAirports = try database.query { db throws(SQLiteError) in
            try db.rows("SELECT ident FROM fix WHERE kind = 'airport' ORDER BY ident") { $0.text(0) }
        }
        let expected = expectedAirports(lines, minimumRunwayFt: minimumRunwayFt)
        var airportMismatches: [String] = []
        for ident in expected.subtracting(databaseAirports).sorted() {
            airportMismatches.append("\(ident): passes the filter, not in the database")
        }
        for ident in Set(databaseAirports).subtracting(expected).sorted() {
            airportMismatches.append("\(ident): in the database, does not pass the filter")
        }
        let airports = databaseAirports.filter(expected.contains)
        let kept = expected

        // Routes of the source file: airport|kind|procedure|route type|transition → number of legs.
        var sourceRoutes: [String: Int] = [:]
        var sourceProcedures: [String: Set<String>] = [:]
        var sourceILS = Set<String>()
        for line in lines where line.count == 132 && char(line, 5) == "P" && char(line, 6) == " " {
            let kind: String
            switch char(line, 13) {
            case "D": kind = NavProcedureKind.sid.rawValue
            case "E": kind = NavProcedureKind.star.rawValue
            case "F": kind = NavProcedureKind.approach.rawValue
            default: continue
            }
            // Primary records only: the continuation number is 0 or 1.
            guard char(line, 39) == "0" || char(line, 39) == "1" else { continue }
            let airport = text(line, 7...10)
            guard kept.contains(airport) else { continue }
            let procedure = text(line, 14...19)
            let routeType = String(char(line, 20))
            sourceRoutes[[airport, kind, procedure, routeType, text(line, 21...25)].joined(separator: "|"), default: 0] += 1
            sourceProcedures[kind, default: []].insert(airport + "|" + procedure)
            if kind == NavProcedureKind.approach.rawValue, routeType == "I" { sourceILS.insert(airport + "|" + procedure) }
        }

        // Routes of the database.
        var databaseRoutes: [String: Int] = [:]
        var databaseProcedures: [String: Int] = [:]
        var databaseILS = 0
        for airport in airports {
            for procedure in try database.procedures(airport: airport, kind: nil) {
                databaseProcedures[procedure.kind.rawValue, default: 0] += 1
                if procedure.kind == .approach, procedure.transitions.contains(where: { $0.routeType == "I" }) { databaseILS += 1 }
                for route in procedure.transitions {
                    let key = [airport, procedure.kind.rawValue, procedure.ident, route.routeType, route.ident].joined(separator: "|")
                    databaseRoutes[key, default: 0] += try database.legs(transitionID: route.id).count
                }
            }
        }
        var routeMismatches: [String] = []
        for key in Set(sourceRoutes.keys).union(databaseRoutes.keys).sorted() where sourceRoutes[key] != databaseRoutes[key] {
            routeMismatches.append("\(key): source \(sourceRoutes[key] ?? 0) legs, database \(databaseRoutes[key] ?? 0) legs")
        }

        // Sample: runways and ILS of airports of different size. The size is the number of procedures.
        var proceduresPerAirport: [String: Int] = [:]
        for key in sourceProcedures.values.flatMap({ $0 }) {
            proceduresPerAirport[String(key.prefix { $0 != "|" }), default: 0] += 1
        }
        var bySize: [(count: Int, ident: String)] = []
        for airport in airports { bySize.append((proceduresPerAirport[airport] ?? 0, airport)) }
        bySize.sort { ($0.count, $0.ident) < ($1.count, $1.ident) }
        let sample = spread(bySize.map(\.ident), count: sampleSize)
        var checks: [VerifyReport.AirportCheck] = []
        var valueMismatches: [String] = []
        for airport in sample {
            let runways = Dictionary(try database.runways(airport: airport).map { ($0.ident, $0) }, uniquingKeysWith: { a, _ in a })
            let localizers = Dictionary(try database.localizers(airport: airport).map { ($0.ident, $0) }, uniquingKeysWith: { a, _ in a })
            var check = VerifyReport.AirportCheck(airport: airport, procedures: proceduresPerAirport[airport] ?? 0,
                                                  runwaysChecked: 0, localizersChecked: 0)
            for line in lines where line.count == 132 && char(line, 5) == "P" && char(line, 6) == " "
                && (char(line, 22) == "0" || char(line, 22) == "1") && text(line, 7...10) == airport {
                switch char(line, 13) {
                case "G":
                    let ident = text(line, 14...18)
                    guard let runway = runways[ident] else {
                        valueMismatches.append("\(airport) \(ident): runway is not in the database")
                        continue
                    }
                    check.runwaysChecked += 1
                    compare(position(line, 33...41, 42...51), runway.fix.position, "\(airport) \(ident) threshold", &valueMismatches)
                    if Int(text(line, 23...27)) != runway.lengthFt {
                        valueMismatches.append("\(airport) \(ident) length: source \(text(line, 23...27)), database \(runway.lengthFt)")
                    }
                case "I":
                    let ident = text(line, 14...17)
                    guard let ils = localizers[ident] else {
                        valueMismatches.append("\(airport) \(ident): localizer is not in the database")
                        continue
                    }
                    check.localizersChecked += 1
                    let frequency = (Double(text(line, 23...27)) ?? -1) / 100
                    if abs(frequency - ils.frequencyMHz) > 0.0001 {
                        valueMismatches.append("\(airport) \(ident) frequency: source \(frequency), database \(ils.frequencyMHz)")
                    }
                    let courseText = text(line, 52...55)
                    let course = courseText.hasSuffix("T") ? Double(courseText.dropLast()) ?? -1 : (Double(courseText) ?? -1) / 10
                    if abs(course - ils.course.degrees) > 0.0001 || courseText.hasSuffix("T") != ils.course.isTrue {
                        valueMismatches.append("\(airport) \(ident) course: source \(courseText), database \(ils.course.degrees)")
                    }
                    if text(line, 28...32) != ils.runway {
                        valueMismatches.append("\(airport) \(ident) runway: source \(text(line, 28...32)), database \(ils.runway)")
                    }
                    compare(position(line, 33...41, 42...51), ils.fix.position, "\(airport) \(ident) localizer", &valueMismatches)
                default:
                    break
                }
            }
            if check.runwaysChecked != runways.count {
                valueMismatches.append("\(airport): \(runways.count) runways in the database, \(check.runwaysChecked) in the source")
            }
            if check.localizersChecked != localizers.count {
                valueMismatches.append("\(airport): \(localizers.count) localizers in the database, \(check.localizersChecked) in the source")
            }
            checks.append(check)
        }

        return VerifyReport(
            cycle: database.info.cycle.ident,
            airports: databaseAirports.count,
            sourceAirports: expected.count,
            airportMismatches: airportMismatches,
            sourceProcedures: sourceProcedures.mapValues(\.count),
            databaseProcedures: databaseProcedures,
            sourceILSApproaches: sourceILS.count,
            databaseILSApproaches: databaseILS,
            sourceLegs: sourceRoutes.values.reduce(0, +),
            databaseLegs: databaseRoutes.values.reduce(0, +),
            routeMismatches: routeMismatches,
            sample: checks,
            valueMismatches: valueMismatches
        )
    }

    /// The airport filter (`AirportFilter`) on the raw columns: surface `H` in the airport record (column 32),
    /// and an ILS of category 1, 2 or 3 (PI column 18) on a runway (PI columns 28-32) of `minimumRunwayFt` or more
    /// (PG columns 23-27).
    static func expectedAirports(_ lines: [[UInt8]], minimumRunwayFt: Int) -> Set<String> {
        var hard = Set<String>()
        var lengths: [String: Int] = [:]
        var ils: [(airport: String, runway: String)] = []
        for line in lines where line.count == 132 && char(line, 5) == "P" && char(line, 6) == " "
            && (char(line, 22) == "0" || char(line, 22) == "1") {
            let airport = text(line, 7...10)
            switch char(line, 13) {
            case "A": if char(line, 32) == "H" { hard.insert(airport) }
            case "G": lengths[airport + "|" + text(line, 14...18)] = Int(text(line, 23...27)) ?? 0
            case "I": if "123".contains(char(line, 18)) { ils.append((airport, text(line, 28...32))) }
            default: break
            }
        }
        var result = Set<String>()
        for item in ils where hard.contains(item.airport) && (lengths[item.airport + "|" + item.runway] ?? 0) >= minimumRunwayFt {
            result.insert(item.airport)
        }
        return result
    }

    /// `count` items at equal steps through the list, the first and the last included.
    static func spread(_ items: [String], count: Int) -> [String] {
        guard items.count > count, count > 1 else { return items }
        return (0..<count).map { items[$0 * (items.count - 1) / (count - 1)] }
    }

    // MARK: Independent reading of the source

    /// Lines as bytes. Carriage returns are removed.
    static func rawLines(_ data: Data) -> [[UInt8]] {
        data.split(separator: 0x0A).map { line in
            Array(line.last == 0x0D ? line.dropLast() : line)
        }
    }

    /// The character of a 1-based column.
    static func char(_ line: [UInt8], _ column: Int) -> Character {
        Character(Unicode.Scalar(line[column - 1]))
    }

    /// Text of 1-based columns without spaces at the ends.
    static func text(_ line: [UInt8], _ columns: ClosedRange<Int>) -> String {
        String(decoding: line[(columns.lowerBound - 1)..<columns.upperBound], as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    /// `N40382374` and `W073464329` (degrees, minutes, seconds, hundredths of seconds).
    static func position(_ line: [UInt8], _ latitude: ClosedRange<Int>, _ longitude: ClosedRange<Int>) -> GeoPoint? {
        func angle(_ field: String, degreeDigits: Int) -> Double? {
            guard field.count == degreeDigits + 7, let sign = field.first else { return nil }
            let digits = field.dropFirst()
            guard let d = Double(digits.prefix(degreeDigits)),
                  let m = Double(digits.dropFirst(degreeDigits).prefix(2)),
                  let s = Double(digits.dropFirst(degreeDigits + 2).prefix(4)) else { return nil }
            let value = d + m / 60 + s / 100 / 3600
            return sign == "S" || sign == "W" ? -value : value
        }
        guard let lat = angle(text(line, latitude), degreeDigits: 2), let lon = angle(text(line, longitude), degreeDigits: 3) else {
            return nil
        }
        return GeoPoint(latDeg: lat, lonDeg: lon)
    }

    static func compare(_ source: GeoPoint?, _ database: GeoPoint, _ name: String, _ mismatches: inout [String]) {
        guard let source else {
            mismatches.append("\(name): the source position is not readable")
            return
        }
        // 1e-7 degree is about 1 cm.
        if abs(source.latDeg - database.latDeg) > 1e-7 || abs(source.lonDeg - database.lonDeg) > 1e-7 {
            mismatches.append("\(name): source \(source.latDeg) \(source.lonDeg), database \(database.latDeg) \(database.lonDeg)")
        }
    }
}
