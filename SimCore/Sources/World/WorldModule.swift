import Kernel
import SimCoreContract

/// World module: the environment of the aircraft. It writes only the `world` section.
///
/// At the first step it makes the environment of the scenario: the destination airport from the navigation
/// database, the terrain elevation, the atmosphere (ISA, temperature deviation, QNH of the destination)
/// and the wind profile. At each step it computes the UTC time and, at the aircraft position of the previous step,
/// the air, the wind and the magnetic variation.
public struct WorldModule: SimModule {
    public static var section: WritableKeyPath<SimState, WorldState> { \.world }

    /// The navigation database. It does not change while the engine exists.
    public let navData: any NavDatabase

    public init(navData: any NavDatabase = EmptyNavDatabase()) {
        self.navData = navData
    }

    public mutating func step(_ section: inout WorldState, reading state: SimState, context: StepContext) {
        let environment = section.environment ?? makeEnvironment(context.initial)
        section.environment = environment

        let position = state.aircraft.position
        let altitude = state.aircraft.altitudeM
        section.utc = UTCTime(context: context)
        section.terrainElevationM = environment.terrainElevationM
        section.air = environment.atmosphere.air(altitudeM: altitude)
        section.wind = environment.windProfile.wind(altitudeM: altitude)
        // WMM needs the height above the ellipsoid. The difference from the altitude above mean sea level
        // (the geoid, less than 110 m) changes the variation by less than 0.001°.
        section.magneticVariationDeg = MagneticModel.current.declination(
            at: position, heightM: altitude, decimalYear: section.utc.decimalYear
        )
    }

    func makeEnvironment(_ initial: InitialConditions) -> WorldEnvironment {
        let destination: DestinationLookup
        do throws(NavDataError) {
            destination = try navData.airport(initial.destinationAirport).map { .found($0) } ?? .notInDatabase
        } catch {
            destination = .failed(error)
        }
        let elevation = Double(destination.airport?.elevationFt ?? 0) * Units.metresPerFoot
        return WorldEnvironment(
            destinationIdent: initial.destinationAirport,
            destination: destination,
            terrainElevationM: elevation,
            atmosphere: Atmosphere(
                qnhPa: initial.weather.qnhHPa * Units.pascalsPerHectopascal,
                isaDeviationK: initial.weather.isaDeviationC,
                fieldElevationM: elevation
            ),
            windProfile: WindProfile(layers: initial.weather.windLayers)
        )
    }
}
