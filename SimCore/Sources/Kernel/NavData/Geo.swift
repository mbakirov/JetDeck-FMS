import Foundation
import SimCoreContract

/// Mean radius of the earth in nautical miles.
public let earthRadiusNM: Double = 3440.065

extension GeoPoint {
    /// Great circle distance in nautical miles (haversine formula on a sphere).
    public func distanceNM(to other: GeoPoint) -> Double {
        let lat1 = latDeg * .pi / 180
        let lat2 = other.latDeg * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.lonDeg - lonDeg) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusNM * asin(min(1, sqrt(a)))
    }
}

/// A box of latitude and longitude that contains a circle. When the circle crosses the meridian 180°,
/// the box has two parts.
public struct GeoBox: Sendable, Equatable {
    public var minLat: Double
    public var maxLat: Double
    public var minLon: Double
    public var maxLon: Double

    public init(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    /// One or two boxes that contain all points not farther than `radiusNM` from `center`.
    public static func around(_ center: GeoPoint, radiusNM: Double) -> [GeoBox] {
        let dLat = radiusNM / earthRadiusNM * 180 / .pi
        let minLat = max(-90, center.latDeg - dLat)
        let maxLat = min(90, center.latDeg + dLat)
        // Near a pole the circle contains all longitudes.
        let farthest = max(abs(minLat), abs(maxLat))
        guard farthest < 89, radiusNM < earthRadiusNM * .pi / 2 else {
            return [GeoBox(minLat: minLat, maxLat: maxLat, minLon: -180, maxLon: 180)]
        }
        let ratio = sin(radiusNM / earthRadiusNM) / cos(center.latDeg * .pi / 180)
        guard ratio < 1 else {
            return [GeoBox(minLat: minLat, maxLat: maxLat, minLon: -180, maxLon: 180)]
        }
        let dLon = asin(ratio) * 180 / .pi
        let west = center.lonDeg - dLon
        let east = center.lonDeg + dLon
        if west < -180 {
            return [GeoBox(minLat: minLat, maxLat: maxLat, minLon: -180, maxLon: east),
                    GeoBox(minLat: minLat, maxLat: maxLat, minLon: west + 360, maxLon: 180)]
        }
        if east > 180 {
            return [GeoBox(minLat: minLat, maxLat: maxLat, minLon: west, maxLon: 180),
                    GeoBox(minLat: minLat, maxLat: maxLat, minLon: -180, maxLon: east - 360)]
        }
        return [GeoBox(minLat: minLat, maxLat: maxLat, minLon: west, maxLon: east)]
    }
}
