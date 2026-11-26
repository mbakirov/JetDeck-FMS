import Foundation
import Kernel
import SimCoreContract
import Testing

func ft(_ feet: Double) -> Double { feet * Units.metresPerFoot }
func kt(_ wind: WindVector) -> Double { wind.speedMps / Units.metresPerSecondPerKnot }

@Test func windVectorDirection() {
    let west = WindVector(fromDirectionDeg: 270, speedMps: 10)
    #expect(abs(west.eastMps - 10) < 1e-12)       // a west wind moves the air to the east
    #expect(abs(west.northMps) < 1e-12)
    #expect(abs(west.fromDirectionDeg - 270) < 1e-12)
    #expect(abs(west.speedMps - 10) < 1e-12)
    #expect(WindVector(fromDirectionDeg: 360, speedMps: 5).fromDirectionDeg < 1e-9)
    #expect(WindVector.calm.fromDirectionDeg == 0)
}

@Test func noLayersIsCalm() {
    #expect(WindProfile.calm.wind(altitudeM: 1000) == .calm)
}

@Test func oneLayerGivesTheSameWindAtAllAltitudes() {
    let profile = WindProfile(layers: [WindLayer(altitudeFt: 5000, directionDeg: 240, speedKt: 30)])
    for altitude in [-100.0, 0, ft(5000), ft(39_000)] {
        #expect(abs(kt(profile.wind(altitudeM: altitude)) - 30) < 1e-9)
        #expect(abs(profile.wind(altitudeM: altitude).fromDirectionDeg - 240) < 1e-9)
    }
}

/// Acceptance criterion: between layers the wind is interpolated; above and below the table the edge layer is used.
@Test func windIsInterpolatedBetweenLayersAndKeptOutsideThem() {
    let profile = WindProfile(layers: [
        WindLayer(altitudeFt: 10_000, directionDeg: 270, speedKt: 40),   // not in order: the profile sorts the layers
        WindLayer(altitudeFt: 2000, directionDeg: 270, speedKt: 20),
        WindLayer(altitudeFt: 20_000, directionDeg: 270, speedKt: 80),
    ])
    #expect(abs(kt(profile.wind(altitudeM: ft(0))) - 20) < 1e-9)
    #expect(abs(kt(profile.wind(altitudeM: ft(2000))) - 20) < 1e-9)
    #expect(abs(kt(profile.wind(altitudeM: ft(6000))) - 30) < 1e-9)
    #expect(abs(kt(profile.wind(altitudeM: ft(15_000))) - 60) < 1e-9)
    #expect(abs(kt(profile.wind(altitudeM: ft(41_000))) - 80) < 1e-9)
    #expect(abs(profile.wind(altitudeM: ft(6000)).fromDirectionDeg - 270) < 1e-9)
}

@Test func directionIsInterpolatedAcrossNorth() {
    let profile = WindProfile(layers: [
        WindLayer(altitudeFt: 0, directionDeg: 350, speedKt: 20),
        WindLayer(altitudeFt: 1000, directionDeg: 10, speedKt: 20),
    ])
    let middle = profile.wind(altitudeM: ft(500))
    #expect(abs(middle.fromDirectionDeg) < 1e-9 || abs(middle.fromDirectionDeg - 360) < 1e-9)
    #expect(abs(kt(middle) - 20 * cos(10 * Double.pi / 180)) < 1e-9)
}

@Test func layersWithTheSameAltitudeUseTheFirst() {
    let profile = WindProfile(layers: [
        WindLayer(altitudeFt: 3000, directionDeg: 90, speedKt: 10),
        WindLayer(altitudeFt: 3000, directionDeg: 180, speedKt: 50),
        WindLayer(altitudeFt: 6000, directionDeg: 90, speedKt: 30),
    ])
    #expect(profile.levels.count == 2)
    #expect(abs(kt(profile.wind(altitudeM: ft(3000))) - 10) < 1e-9)
    #expect(abs(kt(profile.wind(altitudeM: ft(4500))) - 20) < 1e-9)
}
