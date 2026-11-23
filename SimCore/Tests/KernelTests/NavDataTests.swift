import Foundation
import SimCoreContract
import Testing
@testable import Kernel

@Test func greatCircleDistance() {
    let jfk = GeoPoint(latDeg: 40.6399, lonDeg: -73.7787)
    let lax = GeoPoint(latDeg: 33.9425, lonDeg: -118.4081)
    let distance = jfk.distanceNM(to: lax)
    #expect(abs(distance - 2145) < 5)
    #expect(jfk.distanceNM(to: jfk) == 0)
    // One minute of latitude is about one nautical mile.
    #expect(abs(jfk.distanceNM(to: GeoPoint(latDeg: 40.6399 + 1.0 / 60, lonDeg: -73.7787)) - 1) < 0.001)
}

@Test func boxAroundAPoint() {
    let jfk = GeoPoint(latDeg: 40.6399, lonDeg: -73.7787)
    let boxes = GeoBox.around(jfk, radiusNM: 320)
    #expect(boxes.count == 1)
    let box = boxes[0]
    #expect(abs((box.maxLat - box.minLat) - 2 * 320.0 / 60) < 0.05)
    // The east and west points on the circle are inside the box.
    for bearing in stride(from: 0.0, to: 360, by: 5) {
        let point = destination(jfk, bearingDeg: bearing, distanceNM: 319.9)
        #expect(point.latDeg >= box.minLat && point.latDeg <= box.maxLat)
        #expect(point.lonDeg >= box.minLon && point.lonDeg <= box.maxLon, "bearing \(bearing)")
    }
}

@Test func boxAcrossTheMeridian180() {
    let shemya = GeoPoint(latDeg: 52.7123, lonDeg: 174.1136)
    let boxes = GeoBox.around(shemya, radiusNM: 320)
    #expect(boxes.count == 2)
    #expect(boxes.contains { $0.maxLon == 180 })
    #expect(boxes.contains { $0.minLon == -180 && $0.maxLon > -180 })
    let east = destination(shemya, bearingDeg: 90, distanceNM: 300)
    #expect(east.lonDeg < 0)
    #expect(boxes.contains { east.lonDeg >= $0.minLon && east.lonDeg <= $0.maxLon && east.latDeg >= $0.minLat && east.latDeg <= $0.maxLat })
}

@Test func boxNearThePole() {
    let boxes = GeoBox.around(GeoPoint(latDeg: 87, lonDeg: 10), radiusNM: 320)
    #expect(boxes == [GeoBox(minLat: 87 - 320.0 / earthRadiusNM * 180 / .pi, maxLat: 90, minLon: -180, maxLon: 180)])
}

@Test func emptyDatabaseHasNoData() throws {
    let db = EmptyNavDatabase()
    #expect(db.identity == nil)
    #expect(db.cycle == nil)
    #expect(try db.airport("KJFK") == nil)
    #expect(try db.fixes(near: GeoPoint(latDeg: 0, lonDeg: 0), radiusNM: 320, kinds: []).isEmpty)
}

/// The point at a distance and bearing on a sphere.
func destination(_ start: GeoPoint, bearingDeg: Double, distanceNM: Double) -> GeoPoint {
    let d = distanceNM / earthRadiusNM
    let b = bearingDeg * .pi / 180
    let lat1 = start.latDeg * .pi / 180
    let lon1 = start.lonDeg * .pi / 180
    let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
    var lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
    if lon2 > .pi { lon2 -= 2 * .pi }
    if lon2 < -.pi { lon2 += 2 * .pi }
    return GeoPoint(latDeg: lat2 * 180 / .pi, lonDeg: lon2 * 180 / .pi)
}
