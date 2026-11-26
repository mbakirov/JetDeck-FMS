import SimCoreContract

/// State section of the World module. Only the World module writes it.
///
/// The World module is the first module of the step. It computes the values at the aircraft position
/// of the previous step (`SimState.aircraft`). Other modules read them in the same step.
/// Units are SI: Pa, K, kg/m³, m/s, m. Angles are degrees.
public struct WorldState: Sendable, Equatable {
    /// The environment of the scenario. Nil before the first step; after it the same until the end.
    public var environment: WorldEnvironment?
    /// UTC time at the end of the step.
    public var utc: UTCTime
    /// Air at the aircraft.
    public var air: AirState
    /// Wind at the aircraft.
    public var wind: WindVector
    /// Magnetic variation at the aircraft, degrees, east positive.
    public var magneticVariationDeg: Double
    /// Terrain elevation under the aircraft, m. In the MVP it is the elevation of the destination airport.
    public var terrainElevationM: Double

    public init() {
        environment = nil
        utc = UTCTime(date: UTCDate(year: 1970, month: 1, day: 1), secondsOfDay: 0, fraction: 0)
        air = .standard(pressureAltitudeM: 0)
        wind = .calm
        magneticVariationDeg = 0
        terrainElevationM = 0
    }
}

/// The parts of the world that do not change during a scenario.
public struct WorldEnvironment: Sendable, Equatable {
    /// ICAO identifier of the destination airport in the initial conditions.
    public var destinationIdent: String
    /// The destination airport in the navigation database.
    public var destination: DestinationLookup
    /// Terrain elevation, m: the elevation of the destination airport, or 0 when the database does not have it.
    public var terrainElevationM: Double
    /// Atmosphere of the scenario. Other modules use it for other altitudes, for example for predictions.
    public var atmosphere: Atmosphere
    public var windProfile: WindProfile

    public init(destinationIdent: String, destination: DestinationLookup, terrainElevationM: Double,
                atmosphere: Atmosphere, windProfile: WindProfile) {
        self.destinationIdent = destinationIdent
        self.destination = destination
        self.terrainElevationM = terrainElevationM
        self.atmosphere = atmosphere
        self.windProfile = windProfile
    }
}

/// The result of the search for the destination airport.
public enum DestinationLookup: Sendable, Equatable {
    case found(NavAirport)
    /// The database has no airport with this identifier (or the core has no database).
    case notInDatabase
    /// The database cannot be read.
    case failed(NavDataError)

    public var airport: NavAirport? {
        if case .found(let airport) = self { airport } else { nil }
    }
}
