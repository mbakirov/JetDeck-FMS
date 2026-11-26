import Foundation
import Kernel
import Testing

/// Relative tolerance of the acceptance criterion: 0.1 %.
let isaTolerance = 0.001

func relativeError(_ value: Double, _ reference: Double) -> Double {
    abs(value - reference) / abs(reference)
}

/// ISA at geopotential altitudes: temperature K, pressure Pa, density kg/m³.
/// Source: U.S. Standard Atmosphere 1976 (NOAA-S/T 76-1562), table I; the same as ICAO Doc 7488 below 20 km.
@Test(arguments: [
    (0.0, 288.15, 101_325.0, 1.2250),
    (1000.0, 281.65, 89_874.6, 1.11164),
    (2000.0, 275.15, 79_495.2, 1.00649),
    (3000.0, 268.65, 70_108.5, 0.909122),
    (5000.0, 255.65, 54_019.9, 0.736116),
    (8000.0, 236.15, 35_599.8, 0.525168),
    (10_000.0, 223.15, 26_436.3, 0.412707),
    (11_000.0, 216.65, 22_632.1, 0.363918),
    (15_000.0, 216.65, 12_044.6, 0.193674),
    (20_000.0, 216.65, 5_474.89, 0.0880349),
])
func isaMatchesTheStandardTable(altitude: Double, temperature: Double, pressure: Double, density: Double) {
    let air = AirState.standard(pressureAltitudeM: altitude)
    #expect(relativeError(air.temperatureK, temperature) < isaTolerance)
    #expect(relativeError(air.pressurePa, pressure) < isaTolerance)
    #expect(relativeError(air.density, density) < isaTolerance)
}

@Test func isaSpeedOfSound() {
    #expect(abs(ISA.seaLevelSpeedOfSoundMps - 340.294) < 0.001)
    #expect(abs(AirState.standard(pressureAltitudeM: 11_000).speedOfSoundMps - 295.070) < 0.001)
}

@Test(arguments: [-500.0, 0, 1234.5, 10_999, 11_000, 11_001, 15_000, 19_999])
func pressureAltitudeIsTheInverseOfPressure(altitude: Double) {
    #expect(abs(ISA.pressureAltitude(pressurePa: ISA.pressure(pressureAltitudeM: altitude)) - altitude) < 1e-6)
}

@Test func geopotentialAndGeometricAltitudes() {
    #expect(abs(ISA.geopotentialAltitude(geometricM: 11_019.1) - 11_000) < 0.1)
    #expect(abs(ISA.geometricAltitude(geopotentialM: ISA.geopotentialAltitude(geometricM: 12_345)) - 12_345) < 1e-6)
}

@Test func standardAtmosphereAtSeaLevel() {
    let air = Atmosphere.standard.air(altitudeM: 0)
    #expect(abs(air.pressurePa - 101_325) < 1e-6)
    #expect(abs(air.temperatureK - 288.15) < 1e-9)
    #expect(abs(air.pressureAltitudeM) < 1e-6)
}

/// Acceptance criterion: with QNH other than 1013 hPa, the barometric altitude at the airport is the airport elevation.
/// Airports: sea level, KDEN 5434 ft, KASE 7820 ft. This holds for any temperature deviation.
@Test(arguments: [980.0, 1013.25, 1040.0], [0.0, 5434 * 0.3048, 7820 * 0.3048])
func altimeterSetToQNHShowsTheElevationOnTheGround(qnhHPa: Double, elevation: Double) {
    for deviation in [-30.0, 0, 15, 30] {
        let qnh = qnhHPa * 100
        let atmosphere = Atmosphere(qnhPa: qnh, isaDeviationK: deviation, fieldElevationM: elevation)
        let air = atmosphere.air(altitudeM: elevation)
        let shown = Atmosphere.altimeterAltitude(pressureAltitudeM: air.pressureAltitudeM, settingPa: qnh)
        #expect(abs(shown - elevation) < 0.01, "QNH \(qnhHPa), ΔT \(deviation)")
    }
}

@Test func qnhChangesThePressureAltitudeByAboutTwentySevenFeetPerHectopascal() {
    let low = Atmosphere(qnhPa: 100_300, isaDeviationK: 0, fieldElevationM: 0).air(altitudeM: 0)
    #expect(abs(low.pressureAltitudeM / 0.3048 - 280) < 10)   // 10 hPa below standard ≈ +280 ft
}

@Test func warmAirIsAboveTheAltimeterAndColdAirBelow() {
    // Indicated 3000 m above a sea level airport. In warm air the aircraft is higher than the altimeter shows.
    let indicatedHp = 3000.0
    let warm = Atmosphere(qnhPa: 101_325, isaDeviationK: 20, fieldElevationM: 0).altitude(pressureAltitudeM: indicatedHp)
    let standard = Atmosphere.standard.altitude(pressureAltitudeM: indicatedHp)
    let cold = Atmosphere(qnhPa: 101_325, isaDeviationK: -20, fieldElevationM: 0).altitude(pressureAltitudeM: indicatedHp)
    #expect(warm > standard)
    #expect(cold < standard)
    // ΔH = ΔT/L · ln(T0 / (T0 − L·3000)) = 215.6 m. The rule of thumb is 4 % of the height per 10 K.
    #expect(abs((warm - standard) - 215.6) < 0.5)
    #expect(abs((standard - cold) - 215.6) < 0.5)
}

@Test(arguments: [-1000.0, 0, 300, 1655, 5000, 10_500, 11_500, 13_000])
func pressureAltitudeIsTheInverseOfAltitude(altitude: Double) {
    for deviation in [-25.0, 0, 25] {
        let atmosphere = Atmosphere(qnhPa: 99_800, isaDeviationK: deviation, fieldElevationM: 1655)
        #expect(abs(atmosphere.altitude(pressureAltitudeM: atmosphere.pressureAltitude(altitudeM: altitude)) - altitude) < 1e-5)
    }
}

@Test func temperatureDeviationIsTheSameAtAllAltitudes() {
    let atmosphere = Atmosphere(qnhPa: 101_325, isaDeviationK: 12, fieldElevationM: 0)
    for hp in [0.0, 5000, 11_000, 14_000] {
        #expect(abs(atmosphere.air(pressureAltitudeM: hp).temperatureK - ISA.temperature(pressureAltitudeM: hp) - 12) < 1e-9)
    }
}

// MARK: - Air data

@Test func casIsTasAtSeaLevelInISA() {
    let air = AirState.standard(pressureAltitudeM: 0)
    for cas in [50.0, 120, 200] {
        #expect(abs(AirData.tas(casMps: cas, air: air) - cas) < 1e-9)
    }
}

/// Acceptance criterion: at the same calibrated airspeed a temperature deviation changes the true airspeed.
/// CAS 250 kt at FL100: TAS 288.7 kt in ISA. At the same pressure the Mach number is the same,
/// so TAS changes as the square root of the temperature.
@Test func temperatureDeviationChangesTasAtConstantCas() {
    let cas = 250 * Units.metresPerSecondPerKnot
    let pressureAltitude = 10_000 * Units.metresPerFoot
    func tasKt(_ deviation: Double) -> Double {
        let air = Atmosphere(qnhPa: 101_325, isaDeviationK: deviation, fieldElevationM: 0).air(pressureAltitudeM: pressureAltitude)
        return AirData.tas(casMps: cas, air: air) / Units.metresPerSecondPerKnot
    }
    #expect(abs(tasKt(0) - 288.70) < 0.01)
    #expect(abs(tasKt(20) - 299.27) < 0.01)
    #expect(abs(tasKt(-20) - 277.74) < 0.01)
    let isaTemperature = ISA.temperature(pressureAltitudeM: pressureAltitude)
    #expect(abs(tasKt(20) / tasKt(0) - ((isaTemperature + 20) / isaTemperature).squareRoot()) < 1e-12)
}

@Test func machOfCasAtCruise() {
    // CAS 300 kt at FL350: Mach 0.874.
    let air = AirState.standard(pressureAltitudeM: 35_000 * Units.metresPerFoot)
    let mach = AirData.mach(casMps: 300 * Units.metresPerSecondPerKnot, staticPressurePa: air.pressurePa)
    #expect(abs(mach - 0.8736) < 0.0005)
}

@Test func airDataRoundTrips() {
    let air = Atmosphere(qnhPa: 102_000, isaDeviationK: -7, fieldElevationM: 400).air(altitudeM: 6000)
    for tas in [80.0, 150, 230] {
        #expect(abs(AirData.tas(casMps: AirData.cas(tasMps: tas, air: air), air: air) - tas) < 1e-9)
    }
    for mach in [0.2, 0.5, 0.78] {
        #expect(abs(AirData.mach(casMps: AirData.cas(mach: mach, staticPressurePa: air.pressurePa), staticPressurePa: air.pressurePa) - mach) < 1e-12)
    }
    #expect(abs(AirData.totalTemperature(staticTemperatureK: 220, mach: 0.78) - 246.77) < 0.01)
}
