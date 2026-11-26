import Foundation
import Kernel
import SimCoreContract
import Testing

/// Acceptance tolerance of E03: 10 m and 0.01°. The algorithm is much more exact, so the tests use 1 mm and 1e-6°.
let distanceToleranceM = 0.001
let bearingToleranceDeg = 1e-6

/// Reference geodesics on WGS-84: lat1, lon1, azi1, lat2, lon2, azi2, s12 (degrees, metres).
/// Source: GeographicLib-C v2.2, `tests/geodtest.c` (MIT). The values come from the test set of C. Karney,
/// computed with high-precision arithmetic, independently of the double-precision code.
let referenceGeodesics: [[Double]] = [
    [35.60777, -139.44815, 111.098748429560326, -11.17491, -69.95921, 129.289270889708762, 8935244.5604818305],
    [55.52454, 106.05087, 22.020059880982801, 77.03196, 197.18234, 109.112041110671519, 4105086.1713924406],
    [-21.97856, 142.59065, -32.44456876433189, 41.84138, 98.56635, -41.84359951440466, 8394328.894657671],
    [-66.99028, 112.2363, 173.73491240878403, -12.70631, 285.90344, 2.512956620913668, 11150344.2312080241],
    [-17.42761, 173.34268, -159.033557661192928, -15.84784, 5.93557, -20.787484651536988, 16076603.1631180673],
    [32.84994, 48.28919, 150.492927788121982, -56.28556, 202.29132, 48.113449399816759, 16727068.9438164461],
    [-50.56724, -16.30485, -105.439679907590164, -33.56571, -94.97412, -47.348547835650331, 6455670.5118668696],
    [-68.82867, -74.28391, 93.774347763114881, -50.63005, -8.36685, 34.65564085411343, 3956936.926063544],
]

func angleDifference(_ a: Double, _ b: Double) -> Double {
    abs(normalizedDegrees(a - b + 180) - 180)
}

@Test func inverseMatchesReferenceValues() {
    for row in referenceGeodesics {
        let result = Geodesy.inverse(from: GeoPoint(latDeg: row[0], lonDeg: row[1]), to: GeoPoint(latDeg: row[3], lonDeg: row[4]))
        #expect(abs(result.distanceM - row[6]) < distanceToleranceM)
        #expect(angleDifference(result.initialBearingDeg, row[2]) < bearingToleranceDeg)
        #expect(angleDifference(result.finalBearingDeg, row[5]) < bearingToleranceDeg)
        #expect((0..<360).contains(result.initialBearingDeg))
    }
}

@Test func directMatchesReferenceValues() {
    for row in referenceGeodesics {
        let result = Geodesy.direct(from: GeoPoint(latDeg: row[0], lonDeg: row[1]), bearingDeg: row[2], distanceM: row[6])
        let expected = GeoPoint(latDeg: row[3], lonDeg: row[4])
        #expect(Geodesy.inverse(from: result.point, to: expected).distanceM < distanceToleranceM)
        #expect(angleDifference(result.finalBearingDeg, row[5]) < bearingToleranceDeg)
        #expect((-180..<180).contains(result.point.lonDeg))
    }
}

@Test func samePointHasZeroDistance() {
    let point = GeoPoint(latDeg: 40.6398, lonDeg: -73.7789)
    #expect(Geodesy.inverse(from: point, to: point) == Geodesy.Inverse(distanceM: 0, initialBearingDeg: 0, finalBearingDeg: 0))
}

@Test func meridianAndEquatorArcs() {
    // One degree of the equator is a·π/180. One degree of the meridian from the equator is 110 574.389 m.
    let east = Geodesy.inverse(from: GeoPoint(latDeg: 0, lonDeg: 0), to: GeoPoint(latDeg: 0, lonDeg: 1))
    #expect(abs(east.distanceM - Geodesy.equatorialRadiusM * .pi / 180) < distanceToleranceM)
    #expect(east.initialBearingDeg == 90)
    let north = Geodesy.inverse(from: GeoPoint(latDeg: 0, lonDeg: 0), to: GeoPoint(latDeg: 1, lonDeg: 0))
    #expect(abs(north.distanceM - 110_574.389) < 0.001)
    #expect(north.initialBearingDeg == 0)
}

@Test func trackOffsetFromTheEquator() {
    // Path along the equator to the east. The point 1° north of the path is left of it.
    let offset = Geodesy.trackOffset(
        of: GeoPoint(latDeg: 1, lonDeg: 1), from: GeoPoint(latDeg: 0, lonDeg: 0), to: GeoPoint(latDeg: 0, lonDeg: 10)
    )
    #expect(abs(offset.crossTrackM + 110_574.389) < 0.001)
    #expect(abs(offset.alongTrackM - Geodesy.equatorialRadiusM * .pi / 180) < 0.001)
    #expect(abs(offset.foot.latDeg) < 1e-9)
    #expect(abs(offset.bearingAtFootDeg - 90) < 1e-9)
}

@Test(arguments: [
    // start, end, distance along the path to the foot (m), distance from the path (m, positive is right)
    (GeoPoint(latDeg: 40.6398, lonDeg: -73.7789), GeoPoint(latDeg: 42.3656, lonDeg: -71.0096), 50_000.0, 9_260.0),
    (GeoPoint(latDeg: 40.6398, lonDeg: -73.7789), GeoPoint(latDeg: 42.3656, lonDeg: -71.0096), 120_000.0, -400.0),
    (GeoPoint(latDeg: 33.9416, lonDeg: -118.4085), GeoPoint(latDeg: 40.6398, lonDeg: -73.7789), 1_800_000.0, 92_600.0),
    (GeoPoint(latDeg: 61.1744, lonDeg: -149.9964), GeoPoint(latDeg: 21.3187, lonDeg: -157.9225), -30_000.0, -15_000.0),
    (GeoPoint(latDeg: 47.4502, lonDeg: -122.3088), GeoPoint(latDeg: 47.4502, lonDeg: -100.0), 10.0, 0.0),
])
func trackOffsetOfAPointBuiltPerpendicularToThePath(start: GeoPoint, end: GeoPoint, along: Double, cross: Double) {
    // The point is `cross` metres from the path on a geodesic perpendicular to it. Such a point has exactly
    // this cross-track distance, and the foot is at `along` metres from the start.
    let bearing = Geodesy.inverse(from: start, to: end).initialBearingDeg
    let foot = Geodesy.direct(from: start, bearingDeg: bearing, distanceM: along)
    let point = Geodesy.direct(from: foot.point, bearingDeg: foot.finalBearingDeg + 90, distanceM: cross).point

    let offset = Geodesy.trackOffset(of: point, from: start, to: end)
    #expect(abs(offset.crossTrackM - cross) < 0.01)
    #expect(abs(offset.alongTrackM - along) < 0.01)
    #expect(Geodesy.inverse(from: offset.foot, to: foot.point).distanceM < 0.01)
}

@Test func trackOffsetIsTheSameForTheSameInput() {
    let start = GeoPoint(latDeg: 40.6398, lonDeg: -73.7789)
    let end = GeoPoint(latDeg: 42.3656, lonDeg: -71.0096)
    let point = GeoPoint(latDeg: 41.2, lonDeg: -72.1)
    #expect(Geodesy.trackOffset(of: point, from: start, to: end) == Geodesy.trackOffset(of: point, from: start, to: end))
}

@Test func longitudeNormalization() {
    #expect(normalizedLongitude(197.18234) == 197.18234 - 360)
    #expect(normalizedLongitude(-180) == -180)
    #expect(normalizedLongitude(180) == -180)
    #expect(normalizedLongitude(-73.5) == -73.5)
    #expect(normalizedDegrees(-0.5) == 359.5)
    #expect(normalizedDegrees(720) == 0)
}
