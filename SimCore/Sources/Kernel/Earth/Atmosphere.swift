import Foundation

/// The International Standard Atmosphere (ICAO Doc 7488, the same as the U.S. Standard Atmosphere 1976 up to 20 km).
///
/// The functions use the pressure altitude: the altitude of the pressure in ISA (geopotential metres).
/// Two layers: the troposphere up to 11 000 m with a lapse rate of 6.5 K/km, and an isothermal layer above it.
/// Above 20 000 m the isothermal layer continues; the aircraft of this simulator does not fly there.
public enum ISA {
    public static let seaLevelTemperatureK = 288.15
    public static let seaLevelPressurePa = 101_325.0
    public static let seaLevelDensity = 1.225
    /// Temperature lapse rate of the troposphere, K/m.
    public static let lapseRate = 0.0065
    public static let tropopauseAltitudeM = 11_000.0
    public static let tropopauseTemperatureK = 216.65
    /// Standard gravity, m/s².
    public static let gravity = 9.80665
    /// Gas constant of dry air, J/(kg·K).
    public static let gasConstant = 287.05287
    /// Ratio of specific heats of air.
    public static let heatCapacityRatio = 1.4
    /// Radius of the earth for the conversion between geometric and geopotential altitude, m.
    public static let geopotentialEarthRadiusM = 6_356_766.0

    /// Exponent of the pressure in the troposphere: g / (R·L).
    static let pressureExponent = gravity / (gasConstant * lapseRate)
    public static let tropopausePressurePa =
        seaLevelPressurePa * pow(tropopauseTemperatureK / seaLevelTemperatureK, pressureExponent)
    public static let seaLevelSpeedOfSoundMps = speedOfSound(temperatureK: seaLevelTemperatureK)

    public static func temperature(pressureAltitudeM: Double) -> Double {
        pressureAltitudeM < tropopauseAltitudeM
            ? seaLevelTemperatureK - lapseRate * pressureAltitudeM
            : tropopauseTemperatureK
    }

    public static func pressure(pressureAltitudeM: Double) -> Double {
        if pressureAltitudeM < tropopauseAltitudeM {
            let ratio = (seaLevelTemperatureK - lapseRate * pressureAltitudeM) / seaLevelTemperatureK
            return seaLevelPressurePa * pow(ratio, pressureExponent)
        }
        let height = pressureAltitudeM - tropopauseAltitudeM
        return tropopausePressurePa * exp(-gravity * height / (gasConstant * tropopauseTemperatureK))
    }

    /// The pressure altitude of a pressure.
    public static func pressureAltitude(pressurePa: Double) -> Double {
        if pressurePa > tropopausePressurePa {
            let ratio = pow(pressurePa / seaLevelPressurePa, 1 / pressureExponent)
            return seaLevelTemperatureK * (1 - ratio) / lapseRate
        }
        return tropopauseAltitudeM - gasConstant * tropopauseTemperatureK / gravity * log(pressurePa / tropopausePressurePa)
    }

    public static func density(pressurePa: Double, temperatureK: Double) -> Double {
        pressurePa / (gasConstant * temperatureK)
    }

    public static func speedOfSound(temperatureK: Double) -> Double {
        (heatCapacityRatio * gasConstant * temperatureK).squareRoot()
    }

    /// Geopotential altitude of a geometric altitude.
    public static func geopotentialAltitude(geometricM: Double) -> Double {
        geopotentialEarthRadiusM * geometricM / (geopotentialEarthRadiusM + geometricM)
    }

    /// Geometric altitude of a geopotential altitude.
    public static func geometricAltitude(geopotentialM: Double) -> Double {
        geopotentialEarthRadiusM * geopotentialM / (geopotentialEarthRadiusM - geopotentialM)
    }

    /// ∫ dx / T_ISA(x) from 0 to the pressure altitude. The atmosphere with a temperature deviation uses it.
    static func inverseTemperatureIntegral(pressureAltitudeM: Double) -> Double {
        if pressureAltitudeM < tropopauseAltitudeM {
            return log(seaLevelTemperatureK / temperature(pressureAltitudeM: pressureAltitudeM)) / lapseRate
        }
        return log(seaLevelTemperatureK / tropopauseTemperatureK) / lapseRate
            + (pressureAltitudeM - tropopauseAltitudeM) / tropopauseTemperatureK
    }
}

/// Air at one point.
public struct AirState: Sendable, Equatable {
    /// Static pressure, Pa.
    public var pressurePa: Double
    /// Static air temperature, K.
    public var temperatureK: Double
    /// Density, kg/m³.
    public var density: Double
    public var speedOfSoundMps: Double
    /// Pressure altitude, m: the ISA altitude of the static pressure.
    public var pressureAltitudeM: Double

    public init(pressurePa: Double, temperatureK: Double, density: Double, speedOfSoundMps: Double, pressureAltitudeM: Double) {
        self.pressurePa = pressurePa
        self.temperatureK = temperatureK
        self.density = density
        self.speedOfSoundMps = speedOfSoundMps
        self.pressureAltitudeM = pressureAltitudeM
    }

    /// ISA air at the pressure altitude.
    public static func standard(pressureAltitudeM: Double) -> AirState {
        Atmosphere.standard.air(pressureAltitudeM: pressureAltitudeM)
    }
}

/// The atmosphere of a scenario: ISA with a temperature deviation and the QNH of an airport.
///
/// Model:
/// - The temperature is the ISA temperature at the pressure altitude plus the deviation `ΔT`, at all altitudes.
/// - QNH gives the pressure at the airport, as in reality: a pressure altimeter set to QNH shows the airport
///   elevation on the ground, for any temperature. Pressure altitude of the airport = elevation + pressure altitude of QNH.
/// - Between the airport and any other altitude the hydrostatic equation gives dH = (T / T_ISA) · dHp,
///   where H is the geopotential altitude and Hp is the pressure altitude. The integral has a closed form.
///   Thus warm air puts a pressure level higher than in ISA, and cold air puts it lower.
///
/// Altitudes of the public functions are geometric altitudes above mean sea level, in metres.
public struct Atmosphere: Sendable, Equatable {
    public let qnhPa: Double
    public let isaDeviationK: Double
    /// Geometric elevation of the airport of QNH, m.
    public let fieldElevationM: Double
    /// Pressure altitude of the airport, m.
    public let fieldPressureAltitudeM: Double
    /// Geopotential altitude of the airport, m.
    let fieldGeopotentialM: Double

    public init(qnhPa: Double, isaDeviationK: Double, fieldElevationM: Double) {
        self.qnhPa = qnhPa
        self.isaDeviationK = isaDeviationK
        self.fieldElevationM = fieldElevationM
        fieldPressureAltitudeM = ISA.pressureAltitude(pressurePa: qnhPa) + fieldElevationM
        fieldGeopotentialM = ISA.geopotentialAltitude(geometricM: fieldElevationM)
    }

    /// ISA: QNH 1013.25 hPa, no deviation.
    public static let standard = Atmosphere(qnhPa: ISA.seaLevelPressurePa, isaDeviationK: 0, fieldElevationM: 0)

    /// The geopotential altitude in this atmosphere relative to the pressure altitude: H(Hp) - Hp without the constant.
    private func shift(pressureAltitudeM: Double) -> Double {
        pressureAltitudeM + isaDeviationK * ISA.inverseTemperatureIntegral(pressureAltitudeM: pressureAltitudeM)
    }

    /// Geometric altitude of a pressure altitude.
    public func altitude(pressureAltitudeM: Double) -> Double {
        let geopotential = fieldGeopotentialM + shift(pressureAltitudeM: pressureAltitudeM)
            - shift(pressureAltitudeM: fieldPressureAltitudeM)
        return ISA.geometricAltitude(geopotentialM: geopotential)
    }

    /// Pressure altitude at a geometric altitude. Newton's method on `altitude(pressureAltitudeM:)`,
    /// with a fixed upper limit of iterations. The function is monotonic, so 2–3 iterations are enough.
    public func pressureAltitude(altitudeM: Double) -> Double {
        let target = ISA.geopotentialAltitude(geometricM: altitudeM)
        let base = fieldGeopotentialM - shift(pressureAltitudeM: fieldPressureAltitudeM)
        var pressureAltitude = fieldPressureAltitudeM
            + (target - fieldGeopotentialM) * ISA.seaLevelTemperatureK / (ISA.seaLevelTemperatureK + isaDeviationK)
        for _ in 0..<8 {
            let error = base + shift(pressureAltitudeM: pressureAltitude) - target
            // dH/dHp = T / T_ISA.
            let isaTemperature = ISA.temperature(pressureAltitudeM: pressureAltitude)
            let slope = (isaTemperature + isaDeviationK) / isaTemperature
            let correction = error / slope
            pressureAltitude -= correction
            if abs(correction) < 1e-7 { break }
        }
        return pressureAltitude
    }

    /// Air at a pressure altitude.
    public func air(pressureAltitudeM: Double) -> AirState {
        let pressure = ISA.pressure(pressureAltitudeM: pressureAltitudeM)
        let temperature = ISA.temperature(pressureAltitudeM: pressureAltitudeM) + isaDeviationK
        return AirState(
            pressurePa: pressure,
            temperatureK: temperature,
            density: ISA.density(pressurePa: pressure, temperatureK: temperature),
            speedOfSoundMps: ISA.speedOfSound(temperatureK: temperature),
            pressureAltitudeM: pressureAltitudeM
        )
    }

    /// Air at a geometric altitude above mean sea level.
    public func air(altitudeM: Double) -> AirState {
        air(pressureAltitudeM: pressureAltitude(altitudeM: altitudeM))
    }

    /// The altitude that a pressure altimeter shows at a pressure altitude, with the setting `settingPa`.
    /// The altimeter is calibrated in ISA: it shows Hp(p) − Hp(setting).
    public static func altimeterAltitude(pressureAltitudeM: Double, settingPa: Double) -> Double {
        pressureAltitudeM - ISA.pressureAltitude(pressurePa: settingPa)
    }
}
