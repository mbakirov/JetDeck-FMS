import Foundation
import SimCoreContract

/// A spherical harmonic model of the main geomagnetic field, as the World Magnetic Model.
///
/// The algorithm follows the WMM technical report (NOAA NCEI, "The US/UK World Magnetic Model for 2025–2030"):
/// 1. Geodetic coordinates on WGS-84 become geocentric spherical coordinates.
/// 2. The Gauss coefficients change linearly with time from the epoch.
/// 3. The field is the sum over degrees n and orders m with Schmidt semi-normalised associated Legendre functions.
/// 4. The field vector is rotated from the geocentric to the geodetic frame.
///
/// The model is valid for its five years. A date outside this interval uses the nearest end of it.
public struct MagneticModel: Sendable {
    public struct Coefficient: Sendable, Equatable {
        public var n: Int
        public var m: Int
        public var g: Double
        public var h: Double
        public var gDot: Double
        public var hDot: Double

        public init(n: Int, m: Int, g: Double, h: Double, gDot: Double, hDot: Double) {
            self.n = n
            self.m = m
            self.g = g
            self.h = h
            self.gDot = gDot
            self.hDot = hDot
        }
    }

    /// The field vector in the geodetic frame, nT.
    public struct Field: Sendable, Equatable {
        /// X: to true north.
        public var northNT: Double
        /// Y: to east.
        public var eastNT: Double
        /// Z: down.
        public var downNT: Double

        public var horizontalNT: Double { (northNT * northNT + eastNT * eastNT).squareRoot() }
        public var totalNT: Double { (northNT * northNT + eastNT * eastNT + downNT * downNT).squareRoot() }
        /// Declination (magnetic variation): the angle from true north to magnetic north, degrees, east positive.
        public var declinationDeg: Double { atan2(eastNT, northNT) * Units.degreesPerRadian }
        /// Inclination (dip): the angle below the horizontal plane, degrees.
        public var inclinationDeg: Double { atan2(downNT, horizontalNT) * Units.degreesPerRadian }
    }

    public let name: String
    /// Epoch of the coefficients, decimal year.
    public let epoch: Double
    /// End of the valid interval, decimal year.
    public let validUntil: Double
    /// The table in the order of the file.
    public let coefficients: [Coefficient]
    let degree: Int
    // Flat arrays with the index n(n+1)/2 + m.
    private let g: [Double]
    private let h: [Double]
    private let gDot: [Double]
    private let hDot: [Double]
    /// Factors from Gauss-normalised to Schmidt semi-normalised Legendre functions.
    private let schmidt: [Double]

    /// Reference radius of the geomagnetic model, m.
    public static let referenceRadiusM = 6_371_200.0

    public init(name: String, epoch: Double, validUntil: Double, coefficients: [Coefficient]) {
        self.name = name
        self.epoch = epoch
        self.validUntil = validUntil
        self.coefficients = coefficients
        let degree = coefficients.map(\.n).max() ?? 0
        self.degree = degree
        let count = (degree + 1) * (degree + 2) / 2
        var g = [Double](repeating: 0, count: count)
        var h = g, gDot = g, hDot = g
        for c in coefficients where c.n >= 1 && c.m >= 0 && c.m <= c.n {
            let index = c.n * (c.n + 1) / 2 + c.m
            g[index] = c.g
            h[index] = c.h
            gDot[index] = c.gDot
            hDot[index] = c.hDot
        }
        self.g = g
        self.h = h
        self.gDot = gDot
        self.hDot = hDot
        var schmidt = [Double](repeating: 0, count: count)
        schmidt[0] = 1
        if degree >= 1 {
            for n in 1...degree {
                let first = n * (n + 1) / 2
                schmidt[first] = schmidt[(n - 1) * n / 2] * Double(2 * n - 1) / Double(n)
                for m in 1...n {
                    let factor = Double((n - m + 1) * (m == 1 ? 2 : 1)) / Double(n + m)
                    schmidt[first + m] = schmidt[first + m - 1] * factor.squareRoot()
                }
            }
        }
        self.schmidt = schmidt
    }

    /// The field at a point. `heightM` is the height above the WGS-84 ellipsoid.
    public func field(at point: GeoPoint, heightM: Double, decimalYear: Double) -> Field {
        let years = min(max(decimalYear, epoch), validUntil) - epoch

        // 1. Geodetic to geocentric spherical coordinates. At a pole the east direction does not exist,
        //    so the latitude stays a small angle away from it.
        let latitude = min(max(point.latDeg, -89.999_999), 89.999_999) * Units.radiansPerDegree
        let longitude = point.lonDeg * Units.radiansPerDegree
        let a = Geodesy.equatorialRadiusM
        let e2 = Geodesy.flattening * (2 - Geodesy.flattening)
        let sinLatitude = sin(latitude)
        let curvature = a / (1 - e2 * sinLatitude * sinLatitude).squareRoot()
        let p = (curvature + heightM) * cos(latitude)
        let z = (curvature * (1 - e2) + heightM) * sinLatitude
        let radius = (p * p + z * z).squareRoot()
        let geocentricLatitude = asin(z / radius)

        // 2. Legendre functions of sin(geocentric latitude) and their derivatives by the latitude.
        let x = sin(geocentricLatitude)
        let c = cos(geocentricLatitude)
        let count = schmidt.count
        var legendre = [Double](repeating: 0, count: count)
        var derivative = [Double](repeating: 0, count: count)
        legendre[0] = 1
        if degree >= 1 {
            for n in 1...degree {
                for m in 0...n {
                    let index = n * (n + 1) / 2 + m
                    if n == m {
                        let previous = (n - 1) * n / 2 + m - 1
                        legendre[index] = c * legendre[previous]
                        derivative[index] = c * derivative[previous] + x * legendre[previous]
                    } else if n == 1 || m > n - 2 {
                        let previous = (n - 1) * n / 2 + m
                        legendre[index] = x * legendre[previous]
                        derivative[index] = x * derivative[previous] - c * legendre[previous]
                    } else {
                        let previous = (n - 1) * n / 2 + m
                        let beforePrevious = (n - 2) * (n - 1) / 2 + m
                        let k = Double((n - 1) * (n - 1) - m * m) / Double((2 * n - 1) * (2 * n - 3))
                        legendre[index] = x * legendre[previous] - k * legendre[beforePrevious]
                        derivative[index] = x * derivative[previous] - c * legendre[previous] - k * derivative[beforePrevious]
                    }
                }
            }
        }

        // 3. Sum of the series in the geocentric frame. cos(mλ) and sin(mλ) come from the angle sum formulas.
        let cosLongitude = cos(longitude)
        let sinLongitude = sin(longitude)
        var north = 0.0, east = 0.0, down = 0.0
        var radiusPower = (Self.referenceRadiusM / radius) * (Self.referenceRadiusM / radius)
        if degree >= 1 {
            for n in 1...degree {
                radiusPower *= Self.referenceRadiusM / radius     // (a/r)^(n+2)
                var cosM = 1.0, sinM = 0.0
                for m in 0...n {
                    if m > 0 {
                        (cosM, sinM) = (cosM * cosLongitude - sinM * sinLongitude, sinM * cosLongitude + cosM * sinLongitude)
                    }
                    let index = n * (n + 1) / 2 + m
                    let gt = g[index] + gDot[index] * years
                    let ht = h[index] + hDot[index] * years
                    let normalised = legendre[index] * schmidt[index]
                    // The recursion gives dP/dθ of the colatitude; the latitude derivative has the other sign.
                    let normalisedDerivative = -derivative[index] * schmidt[index]
                    let cosTerm = gt * cosM + ht * sinM
                    north -= radiusPower * cosTerm * normalisedDerivative
                    east += radiusPower * Double(m) * (gt * sinM - ht * cosM) * normalised
                    down -= radiusPower * Double(n + 1) * cosTerm * normalised
                }
            }
        }
        east /= c

        // 4. Rotation from the geocentric to the geodetic frame.
        let psi = geocentricLatitude - latitude
        return Field(
            northNT: north * cos(psi) - down * sin(psi),
            eastNT: east,
            downNT: north * sin(psi) + down * cos(psi)
        )
    }

    /// Magnetic variation, degrees, east positive.
    public func declination(at point: GeoPoint, heightM: Double, decimalYear: Double) -> Double {
        field(at: point, heightM: heightM, decimalYear: decimalYear).declinationDeg
    }
}
