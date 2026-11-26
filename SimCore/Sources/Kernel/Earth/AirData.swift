import Foundation

/// Air data: conversions between calibrated airspeed (CAS), Mach number and true airspeed (TAS).
///
/// Formulas for compressible subsonic flow (Saint-Venant). CAS is the speed that gives the same impact
/// pressure in ISA at sea level. Speeds are in m/s. Supersonic flow is not a case of this simulator.
public enum AirData {
    private static let exponent = ISA.heatCapacityRatio / (ISA.heatCapacityRatio - 1)       // 3.5
    private static let factor = (ISA.heatCapacityRatio - 1) / 2                             // 0.2

    /// Impact pressure (total minus static pressure) of a Mach number.
    public static func impactPressure(mach: Double, staticPressurePa: Double) -> Double {
        staticPressurePa * (pow(1 + factor * mach * mach, exponent) - 1)
    }

    /// Mach number of an impact pressure.
    public static func mach(impactPressurePa: Double, staticPressurePa: Double) -> Double {
        (max(0, pow(impactPressurePa / staticPressurePa + 1, 1 / exponent) - 1) / factor).squareRoot()
    }

    /// Impact pressure of a calibrated airspeed.
    public static func impactPressure(casMps: Double) -> Double {
        impactPressure(mach: casMps / ISA.seaLevelSpeedOfSoundMps, staticPressurePa: ISA.seaLevelPressurePa)
    }

    /// Calibrated airspeed of an impact pressure.
    public static func cas(impactPressurePa: Double) -> Double {
        mach(impactPressurePa: impactPressurePa, staticPressurePa: ISA.seaLevelPressurePa) * ISA.seaLevelSpeedOfSoundMps
    }

    public static func mach(casMps: Double, staticPressurePa: Double) -> Double {
        mach(impactPressurePa: impactPressure(casMps: casMps), staticPressurePa: staticPressurePa)
    }

    public static func cas(mach: Double, staticPressurePa: Double) -> Double {
        cas(impactPressurePa: impactPressure(mach: mach, staticPressurePa: staticPressurePa))
    }

    /// True airspeed of a calibrated airspeed in the air `air`.
    /// At the same pressure the Mach number is the same, and TAS = Mach · speed of sound grows with the temperature.
    public static func tas(casMps: Double, air: AirState) -> Double {
        mach(casMps: casMps, staticPressurePa: air.pressurePa) * air.speedOfSoundMps
    }

    /// Calibrated airspeed of a true airspeed in the air `air`.
    public static func cas(tasMps: Double, air: AirState) -> Double {
        cas(mach: tasMps / air.speedOfSoundMps, staticPressurePa: air.pressurePa)
    }

    /// Total air temperature (recovery factor 1).
    public static func totalTemperature(staticTemperatureK: Double, mach: Double) -> Double {
        staticTemperatureK * (1 + factor * mach * mach)
    }
}
