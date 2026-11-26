import SimCoreContract

/// State section of the Aircraft module. Only the Aircraft module writes it.
///
/// `SimState(initial:)` sets the values of step 0. The World module reads the position
/// of the previous step, because World is the first module of the step.
public struct AircraftState: Sendable, Equatable {
    /// Position of the aircraft reference point.
    public var position: GeoPoint
    /// Geometric altitude above mean sea level, in metres.
    public var altitudeM: Double

    public init() {
        position = GeoPoint(latDeg: 0, lonDeg: 0)
        altitudeM = 0
    }

    /// The state at step 0.
    public init(initial: InitialAircraft) {
        position = initial.position
        altitudeM = initial.altitudeFt * Units.metresPerFoot
    }
}
