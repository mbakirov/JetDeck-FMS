internal import CGeodesic
import Foundation
import SimCoreContract

/// Geodesics on the WGS-84 ellipsoid: the shortest path between two points.
///
/// The direct and the inverse problems use the algorithm of C. F. F. Karney (GeographicLib-C, MIT).
/// The error is a few nanometres for any two points. Distances are in metres, bearings are true, in degrees 0..<360.
public enum Geodesy {
    /// Equatorial radius of WGS-84, in metres.
    public static let equatorialRadiusM = 6_378_137.0
    /// Flattening of WGS-84.
    public static let flattening = 1 / 298.257223563

    /// The ellipsoid for the C functions. The first call of `geod_init` sets the constants of the C code.
    /// A static constant is initialised once and before the first use, so the C code never writes them in parallel.
    private static let wgs84: geod_geodesic = {
        var geodesic = geod_geodesic()
        geod_init(&geodesic, equatorialRadiusM, flattening)
        return geodesic
    }()

    /// The result of the inverse problem.
    public struct Inverse: Sendable, Equatable {
        public var distanceM: Double
        /// Bearing of the path at the start point.
        public var initialBearingDeg: Double
        /// Bearing of the path at the end point (the direction of travel, not the bearing back).
        public var finalBearingDeg: Double

        public init(distanceM: Double, initialBearingDeg: Double, finalBearingDeg: Double) {
            self.distanceM = distanceM
            self.initialBearingDeg = initialBearingDeg
            self.finalBearingDeg = finalBearingDeg
        }

        public var distanceNM: Double { distanceM / Units.metresPerNauticalMile }
    }

    /// The result of the direct problem.
    public struct Direct: Sendable, Equatable {
        public var point: GeoPoint
        /// Bearing of the path at the end point.
        public var finalBearingDeg: Double

        public init(point: GeoPoint, finalBearingDeg: Double) {
            self.point = point
            self.finalBearingDeg = finalBearingDeg
        }
    }

    /// The position of a point relative to a path.
    public struct TrackOffset: Sendable, Equatable {
        /// Distance from the path. Positive when the point is right of the path, negative when it is left.
        public var crossTrackM: Double
        /// Distance along the path from its start to the nearest point of the path.
        /// Negative before the start. It can be longer than the path.
        public var alongTrackM: Double
        /// The nearest point of the path (or of its extension).
        public var foot: GeoPoint
        /// Bearing of the path at `foot`.
        public var bearingAtFootDeg: Double

        public init(crossTrackM: Double, alongTrackM: Double, foot: GeoPoint, bearingAtFootDeg: Double) {
            self.crossTrackM = crossTrackM
            self.alongTrackM = alongTrackM
            self.foot = foot
            self.bearingAtFootDeg = bearingAtFootDeg
        }
    }

    /// Distance and bearings from `start` to `end` (the inverse problem).
    /// For the same point the distance is 0 and the bearings are 0.
    public static func inverse(from start: GeoPoint, to end: GeoPoint) -> Inverse {
        var geodesic = wgs84
        var distance = 0.0, azimuth1 = 0.0, azimuth2 = 0.0
        geod_inverse(&geodesic, start.latDeg, start.lonDeg, end.latDeg, end.lonDeg, &distance, &azimuth1, &azimuth2)
        if distance == 0 {
            return Inverse(distanceM: 0, initialBearingDeg: 0, finalBearingDeg: 0)
        }
        return Inverse(
            distanceM: distance,
            initialBearingDeg: normalizedDegrees(azimuth1),
            finalBearingDeg: normalizedDegrees(azimuth2)
        )
    }

    /// The point at `distanceM` from `start` on the path with the bearing `bearingDeg` at `start` (the direct problem).
    /// A negative distance goes back along the path.
    public static func direct(from start: GeoPoint, bearingDeg: Double, distanceM: Double) -> Direct {
        var geodesic = wgs84
        var latitude = 0.0, longitude = 0.0, azimuth2 = 0.0
        geod_direct(&geodesic, start.latDeg, start.lonDeg, bearingDeg, distanceM, &latitude, &longitude, &azimuth2)
        return Direct(
            point: GeoPoint(latDeg: latitude, lonDeg: normalizedLongitude(longitude)),
            finalBearingDeg: normalizedDegrees(azimuth2)
        )
    }

    /// Position of `point` relative to the path from `start` to `end`.
    public static func trackOffset(of point: GeoPoint, from start: GeoPoint, to end: GeoPoint) -> TrackOffset {
        trackOffset(of: point, from: start, bearingDeg: inverse(from: start, to: end).initialBearingDeg)
    }

    /// Position of `point` relative to the path that leaves `start` with the bearing `bearingDeg`.
    ///
    /// The nearest point of the path is found by iteration (C. Baselga, J. C. Martínez-Llario,
    /// "Intersection and point-to-line solutions for geodesics on the ellipsoid", Stud. Geophys. Geod. 62, 2018).
    /// Each iteration moves the start along the path by the along-track distance on a sphere.
    /// At the nearest point the path is perpendicular to the direction to `point`, and the iteration stops.
    public static func trackOffset(of point: GeoPoint, from start: GeoPoint, bearingDeg: Double) -> TrackOffset {
        let radius = 6_371_008.8   // mean radius of the earth. It changes only the speed of the iteration.
        var foot = start
        var bearing = normalizedDegrees(bearingDeg)
        var along = 0.0
        for _ in 0..<maximumIterations {
            let toPoint = inverse(from: foot, to: point)
            if toPoint.distanceM == 0 { break }
            let angle = (toPoint.initialBearingDeg - bearing) * Units.radiansPerDegree
            let step = radius * atan(tan(toPoint.distanceM / radius) * cos(angle))
            // `atan` gives the nearest of two perpendicular points. A point more than a quarter
            // of the earth away from the path is not a case of this simulator.
            if abs(step) < convergenceM { break }
            let moved = direct(from: foot, bearingDeg: bearing, distanceM: step)
            foot = moved.point
            bearing = moved.finalBearingDeg
            along += step
        }
        let toPoint = inverse(from: foot, to: point)
        let side = sin((toPoint.initialBearingDeg - bearing) * Units.radiansPerDegree)
        return TrackOffset(
            crossTrackM: side < 0 ? -toPoint.distanceM : toPoint.distanceM,
            alongTrackM: along,
            foot: foot,
            bearingAtFootDeg: bearing
        )
    }

    /// The iteration of `trackOffset` stops when the start moves less than this distance.
    static let convergenceM = 1e-4
    /// A fixed upper limit keeps the work of a step bounded. Usually 2–4 iterations are enough.
    static let maximumIterations = 20
}

/// A longitude in -180..<180.
@inlinable
public func normalizedLongitude(_ degrees: Double) -> Double {
    let shifted = normalizedDegrees(degrees + 180)
    return shifted - 180
}
