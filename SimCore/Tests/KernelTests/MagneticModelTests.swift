import Foundation
import Kernel
import SimCoreContract
import Testing

let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures")

/// Rows of a NOAA test value file without comments.
func testValueRows(_ name: String) throws -> [[Double]] {
    try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        .split(separator: "\n")
        .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { $0.split(separator: " ").map { Double($0) ?? .nan } }
}

@Test func wmmCoefficientsAreTheSameAsTheFile() throws {
    let lines = try String(contentsOf: fixtures.appendingPathComponent("WMM2025.COF"), encoding: .utf8)
        .split(separator: "\n")
    #expect(lines[0].split(separator: " ").map(String.init) == ["2025.0", "WMM-2025", "11/13/2024"])
    let rows = lines.dropFirst().prefix { !$0.hasPrefix("9999") }.map { line in
        let f = line.split(separator: " ").map { Double($0)! }
        return MagneticModel.Coefficient(n: Int(f[0]), m: Int(f[1]), g: f[2], h: f[3], gDot: f[4], hDot: f[5])
    }
    #expect(rows.count == 90)
    #expect(MagneticModel.wmm2025.coefficients == rows)
    #expect(MagneticModel.wmm2025.epoch == 2025.0)
}

/// Acceptance criterion: the declination is the same as the NOAA test values.
/// File of the WMM2025 report (12 points): date, height km, lat, lon, X, Y, Z, H, F, I, D, ...
@Test func wmmMatchesTheTestValuesOfTheReport() throws {
    let rows = try testValueRows("WMM2025-TestValues-report.txt")
    #expect(rows.count == 12)
    for row in rows {
        let field = MagneticModel.wmm2025.field(
            at: GeoPoint(latDeg: row[2], lonDeg: row[3]), heightM: row[1] * 1000, decimalYear: row[0]
        )
        // The file gives X, Y, Z to 0.1 nT and D to 0.01°.
        #expect(abs(field.northNT - row[4]) <= 0.05 + 1e-6, "X at \(row[0...3])")
        #expect(abs(field.eastNT - row[5]) <= 0.05 + 1e-6, "Y at \(row[0...3])")
        #expect(abs(field.downNT - row[6]) <= 0.05 + 1e-6, "Z at \(row[0...3])")
        #expect(abs(field.inclinationDeg - row[9]) <= 0.005 + 1e-9)
        #expect(abs(field.declinationDeg - row[10]) <= 0.005 + 1e-9, "D at \(row[0...3])")
    }
}

/// 100 points of the coefficient package: date, height km, lat, lon, D, I, H, X, Y, Z, F, ...
/// X, Y, Z have 6 decimals: the sum of the series must be the same as in the NOAA software.
@Test func wmmMatchesTheTestValuesOfTheCoefficientPackage() throws {
    let rows = try testValueRows("WMM2025-TestValues-100.txt")
    #expect(rows.count == 100)
    for row in rows {
        let field = MagneticModel.wmm2025.field(
            at: GeoPoint(latDeg: row[2], lonDeg: row[3]), heightM: row[1] * 1000, decimalYear: row[0]
        )
        #expect(abs(field.declinationDeg - row[4]) <= 0.005 + 1e-9, "D at \(row[0...3])")
        #expect(abs(field.inclinationDeg - row[5]) <= 0.005 + 1e-9, "I at \(row[0...3])")
        #expect(abs(field.northNT - row[7]) < 1e-3, "X at \(row[0...3])")
        #expect(abs(field.eastNT - row[8]) < 1e-3, "Y at \(row[0...3])")
        #expect(abs(field.downNT - row[9]) < 1e-3, "Z at \(row[0...3])")
    }
}

@Test func datesOutsideTheModelUseTheNearestEnd() {
    let point = GeoPoint(latDeg: 40.64, lonDeg: -73.78)
    let model = MagneticModel.wmm2025
    #expect(model.declination(at: point, heightM: 0, decimalYear: 2020) == model.declination(at: point, heightM: 0, decimalYear: 2025))
    #expect(model.declination(at: point, heightM: 0, decimalYear: 2035) == model.declination(at: point, heightM: 0, decimalYear: 2030))
}

@Test func declinationInTheUnitedStates() {
    // Signs and sizes known from the charts: west variation in New York, east in Seattle.
    let model = MagneticModel.wmm2025
    let jfk = model.declination(at: GeoPoint(latDeg: 40.64, lonDeg: -73.78), heightM: 0, decimalYear: 2026.9)
    let sea = model.declination(at: GeoPoint(latDeg: 47.45, lonDeg: -122.31), heightM: 0, decimalYear: 2026.9)
    #expect(jfk < -12 && jfk > -14)
    #expect(sea > 14 && sea < 16)
}

@Test func fieldAtThePoleIsFinite() {
    let field = MagneticModel.wmm2025.field(at: GeoPoint(latDeg: 90, lonDeg: 0), heightM: 0, decimalYear: 2026)
    #expect(field.declinationDeg.isFinite)
    #expect(field.totalNT.isFinite)
}
