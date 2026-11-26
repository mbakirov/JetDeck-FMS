import Foundation
import SimCoreContract

/// Wind as a velocity of the air relative to the ground. The components point to where the air moves.
public struct WindVector: Sendable, Equatable {
    /// Speed to true north, m/s.
    public var northMps: Double
    /// Speed to east, m/s.
    public var eastMps: Double

    public init(northMps: Double, eastMps: Double) {
        self.northMps = northMps
        self.eastMps = eastMps
    }

    /// Wind from the true direction `fromDirectionDeg` (meteorological convention).
    public init(fromDirectionDeg: Double, speedMps: Double) {
        let radians = fromDirectionDeg * Units.radiansPerDegree
        northMps = -speedMps * cos(radians)
        eastMps = -speedMps * sin(radians)
    }

    public static let calm = WindVector(northMps: 0, eastMps: 0)

    public var speedMps: Double { (northMps * northMps + eastMps * eastMps).squareRoot() }

    /// True direction from which the wind blows, 0..<360. Zero for calm.
    public var fromDirectionDeg: Double {
        speedMps == 0 ? 0 : normalizedDegrees(atan2(-eastMps, -northMps) * Units.degreesPerRadian)
    }
}

/// Wind at all altitudes, from the wind layers of the scenario.
///
/// Between two layers the north and east components are interpolated linearly by altitude.
/// The interpolation of components has no problem with the direction across north, and two opposite winds
/// give a calm between them. Below the lowest layer and above the highest layer the wind is the wind of that layer.
/// No layers means calm.
public struct WindProfile: Sendable, Equatable {
    public struct Level: Sendable, Equatable {
        /// Geometric altitude above mean sea level, m.
        public var altitudeM: Double
        public var wind: WindVector
    }

    /// Levels in order of altitude. Each altitude is in the list once.
    public let levels: [Level]

    /// Layers with the same altitude: the first of them in the list is used.
    public init(layers: [WindLayer]) {
        let sorted = layers.enumerated().sorted {
            ($0.element.altitudeFt, $0.offset) < ($1.element.altitudeFt, $1.offset)
        }
        var levels: [Level] = []
        for (_, layer) in sorted where levels.last.map({ $0.altitudeM != layer.altitudeFt * Units.metresPerFoot }) ?? true {
            levels.append(Level(
                altitudeM: layer.altitudeFt * Units.metresPerFoot,
                wind: WindVector(fromDirectionDeg: layer.directionDeg, speedMps: layer.speedKt * Units.metresPerSecondPerKnot)
            ))
        }
        self.levels = levels
    }

    public static let calm = WindProfile(layers: [])

    /// Wind at a geometric altitude above mean sea level, m.
    public func wind(altitudeM: Double) -> WindVector {
        guard let first = levels.first, let last = levels.last else { return .calm }
        if altitudeM <= first.altitudeM { return first.wind }
        if altitudeM >= last.altitudeM { return last.wind }
        // The first level above the altitude. The list is short (a few layers), a linear search is enough.
        let upper = levels.firstIndex { $0.altitudeM > altitudeM }!
        let below = levels[upper - 1]
        let above = levels[upper]
        let t = (altitudeM - below.altitudeM) / (above.altitudeM - below.altitudeM)
        return WindVector(
            northMps: below.wind.northMps + (above.wind.northMps - below.wind.northMps) * t,
            eastMps: below.wind.eastMps + (above.wind.eastMps - below.wind.eastMps) * t
        )
    }
}
