import Foundation
import SimCoreContract

/// An error of the navigation database.
public enum NavDataError: Error, Sendable, Equatable, LocalizedError {
    /// The file cannot be opened or read.
    case storage(String)
    /// The file has a schema version that this build does not support.
    case schemaMismatch(found: Int, expected: Int)
    /// The file is not a navigation database or its data is not valid.
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .storage(let reason): "Navigation database cannot be read: \(reason)"
        case .schemaMismatch(let found, let expected): "Navigation database has schema version \(found). This build supports version \(expected)."
        case .invalid(let reason): "Navigation database is not valid: \(reason)"
        }
    }
}

/// Read-only access to the navigation database.
///
/// Rules for all implementations:
/// - The data does not change while the object exists. A new database is a new object (and a new `SimEngine`).
/// - Each result has a fixed order. The order does not depend on the order of a `Set` or a `Dictionary`.
/// - Identifiers are compared exactly (upper case, as in ARINC 424).
public protocol NavDatabase: Sendable {
    /// Identity of the data. Nil for a database without data (`EmptyNavDatabase`).
    var identity: NavDataIdentity? { get }

    func airport(_ ident: String) throws(NavDataError) -> NavAirport?
    /// Runways of an airport, ordered by identifier.
    func runways(airport: String) throws(NavDataError) -> [NavRunway]
    /// ILS, LOC, LDA, SDF and IGS of an airport, ordered by identifier.
    func localizers(airport: String) throws(NavDataError) -> [NavILS]
    /// All fixes of any kind with this identifier, ordered by kind, region, airport and row.
    func fixes(ident: String) throws(NavDataError) -> [NavFix]
    /// Navaids with this identifier, ordered by region, airport and row.
    func navaids(ident: String) throws(NavDataError) -> [NavNavaid]
    /// Waypoints with this identifier, ordered by region, airport and row.
    func waypoints(ident: String) throws(NavDataError) -> [NavWaypoint]
    /// Procedures of an airport with their routes. Ordered by kind and identifier. Nil `kind` gives all kinds.
    func procedures(airport: String, kind: NavProcedureKind?) throws(NavDataError) -> [NavProcedure]
    /// Legs of one route of a procedure, ordered by sequence number.
    func legs(transitionID: Int64) throws(NavDataError) -> [NavProcedureLeg]
    /// Fixes of all airways with this name, ordered by segment and then by sequence number.
    /// Each segment (`NavAirwayFix.segment`) is a continuous airway.
    func airway(_ route: String) throws(NavDataError) -> [NavAirwayFix]
    /// Fixes inside a circle, for the map of the ND. Ordered by distance from the center, then by row.
    /// `kinds` limits the result to these kinds. All kinds when it is empty.
    func fixes(near center: GeoPoint, radiusNM: Double, kinds: Set<NavFixKind>) throws(NavDataError) -> [NavFix]
}

extension NavDatabase {
    /// The AIRAC cycle for the A/C STATUS page.
    public var cycle: AIRACCycle? { identity?.cycle }
}

/// A database without data. The core uses it when no navigation database is given.
public struct EmptyNavDatabase: NavDatabase {
    public init() {}

    public var identity: NavDataIdentity? { nil }
    public func airport(_ ident: String) throws(NavDataError) -> NavAirport? { nil }
    public func runways(airport: String) throws(NavDataError) -> [NavRunway] { [] }
    public func localizers(airport: String) throws(NavDataError) -> [NavILS] { [] }
    public func fixes(ident: String) throws(NavDataError) -> [NavFix] { [] }
    public func navaids(ident: String) throws(NavDataError) -> [NavNavaid] { [] }
    public func waypoints(ident: String) throws(NavDataError) -> [NavWaypoint] { [] }
    public func procedures(airport: String, kind: NavProcedureKind?) throws(NavDataError) -> [NavProcedure] { [] }
    public func legs(transitionID: Int64) throws(NavDataError) -> [NavProcedureLeg] { [] }
    public func airway(_ route: String) throws(NavDataError) -> [NavAirwayFix] { [] }
    public func fixes(near center: GeoPoint, radiusNM: Double, kinds: Set<NavFixKind>) throws(NavDataError) -> [NavFix] { [] }
}
