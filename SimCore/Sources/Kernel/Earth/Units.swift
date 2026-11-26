/// Unit conversions. The formulas of the core use SI units. The snapshot uses the units of the displays.
public enum Units {
    public static let metresPerFoot = 0.3048
    public static let metresPerNauticalMile = 1852.0
    /// Metres per second in one knot.
    public static let metresPerSecondPerKnot = 1852.0 / 3600.0
    public static let pascalsPerHectopascal = 100.0
    /// Kelvin at 0 °C.
    public static let zeroCelsiusKelvin = 273.15
    public static let degreesPerRadian = 180.0 / Double.pi
    public static let radiansPerDegree = Double.pi / 180.0
}

/// Smallest non-negative remainder: the result is in 0..<divisor for any sign of the value.
@inlinable
func floorMod(_ value: Int, _ divisor: Int) -> Int {
    let r = value % divisor
    return r < 0 ? r + divisor : r
}

/// Division that rounds down for any sign of the value.
@inlinable
func floorDiv(_ value: Int, _ divisor: Int) -> Int {
    (value - floorMod(value, divisor)) / divisor
}

/// An angle in degrees in 0..<360.
@inlinable
public func normalizedDegrees(_ degrees: Double) -> Double {
    let r = degrees.truncatingRemainder(dividingBy: 360)
    let positive = r < 0 ? r + 360 : r
    return positive >= 360 ? 0 : positive
}
