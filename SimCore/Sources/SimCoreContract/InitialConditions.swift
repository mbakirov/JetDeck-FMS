import Foundation

/// The state of the core before the first step.
/// The same initial conditions and the same events always give the same snapshots.
///
/// The scenario file (E11) gives these values. The default values of the initialiser are for tests and tools.
public struct InitialConditions: Sendable, Codable, Equatable {
    public var scenarioID: String
    public var settings: CoreSettings
    /// UTC date at step 0.
    public var utcStartDate: UTCDate
    /// UTC time at step 0, in seconds from midnight.
    public var utcStartSecondsOfDay: Int
    /// Seed for all random effects (wind, turbulence). The core has no other source of randomness.
    public var seed: UInt64
    /// Position of the aircraft at step 0.
    public var aircraft: InitialAircraft
    /// ICAO identifier of the destination airport, for example "KJFK".
    /// Its elevation is the terrain elevation, and the QNH of the weather is the QNH of this airport.
    public var destinationAirport: String
    public var weather: WeatherConditions

    public init(
        scenarioID: String,
        settings: CoreSettings,
        utcStartDate: UTCDate = UTCDate(year: 2026, month: 1, day: 1),
        utcStartSecondsOfDay: Int,
        seed: UInt64,
        aircraft: InitialAircraft = InitialAircraft(position: GeoPoint(latDeg: 0, lonDeg: 0), altitudeFt: 0),
        destinationAirport: String = "",
        weather: WeatherConditions = .standard
    ) {
        self.scenarioID = scenarioID
        self.settings = settings
        self.utcStartDate = utcStartDate
        self.utcStartSecondsOfDay = utcStartSecondsOfDay
        self.seed = seed
        self.aircraft = aircraft
        self.destinationAirport = destinationAirport
        self.weather = weather
    }
}

/// A date of the Gregorian calendar in UTC.
/// A date that does not exist (for example 30 February) counts forward from the first day of the month.
public struct UTCDate: Sendable, Codable, Equatable, Hashable {
    public var year: Int
    /// 1...12.
    public var month: Int
    /// 1...31.
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

/// The aircraft at step 0. E04 and E11 add speed, attitude, configuration and fuel.
public struct InitialAircraft: Sendable, Codable, Equatable {
    public var position: GeoPoint
    /// Geometric altitude above mean sea level, in feet.
    public var altitudeFt: Double

    public init(position: GeoPoint, altitudeFt: Double) {
        self.position = position
        self.altitudeFt = altitudeFt
    }
}

/// The weather of the scenario. It does not change during the scenario.
public struct WeatherConditions: Sendable, Codable, Equatable {
    /// QNH of the destination airport, in hPa.
    public var qnhHPa: Double
    /// Difference between the air temperature and the ISA temperature, in °C. The same at all altitudes.
    public var isaDeviationC: Double
    /// Wind layers in any order. Between two layers the wind is interpolated.
    /// Below the lowest layer and above the highest layer the wind is the wind of that layer.
    /// No layers means no wind.
    public var windLayers: [WindLayer]

    public init(qnhHPa: Double, isaDeviationC: Double, windLayers: [WindLayer]) {
        self.qnhHPa = qnhHPa
        self.isaDeviationC = isaDeviationC
        self.windLayers = windLayers
    }

    /// ISA, QNH 1013.25 hPa, no wind.
    public static let standard = WeatherConditions(qnhHPa: 1013.25, isaDeviationC: 0, windLayers: [])
}

/// The wind at one altitude.
public struct WindLayer: Sendable, Codable, Equatable {
    /// Geometric altitude above mean sea level, in feet.
    public var altitudeFt: Double
    /// True direction from which the wind blows, in degrees.
    public var directionDeg: Double
    public var speedKt: Double

    public init(altitudeFt: Double, directionDeg: Double, speedKt: Double) {
        self.altitudeFt = altitudeFt
        self.directionDeg = directionDeg
        self.speedKt = speedKt
    }
}
