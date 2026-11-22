import Foundation
import Kernel
import SimCoreContract
import Synchronization

/// Reads the navigation database file. Read only.
///
/// The file is opened with `immutable=1`: it must not change while the reader exists.
/// To use a new database, make a new reader (and a new `SimEngine`).
/// The reader is safe to use from any thread. Calls are serialised.
public final class NavDatabaseReader: NavDatabase {
    public let path: String
    public let info: NavDataIdentity
    private let connection: Mutex<SQLiteDatabase>

    public var identity: NavDataIdentity? { info }

    public init(path: String) throws(NavDataError) {
        guard FileManager.default.fileExists(atPath: path) else { throw .storage("file not found: \(path)") }
        let db: SQLiteDatabase
        do {
            db = try SQLiteDatabase(path: path, mode: .readOnlyImmutable)
        } catch {
            throw .storage(error.description)
        }
        self.path = path
        self.info = try Self.readIdentity(db)
        self.connection = Mutex(db)
    }

    private static func readIdentity(_ db: SQLiteDatabase) throws(NavDataError) -> NavDataIdentity {
        let version: Int
        let meta: [String: String]
        do {
            guard case .integer(let v)? = try db.scalar("PRAGMA user_version") else { throw NavDataError.invalid("no user_version") }
            version = Int(v)
            guard version == NavDBSchema.version else { throw NavDataError.schemaMismatch(found: version, expected: NavDBSchema.version) }
            let pairs = try db.rows("SELECT key, value FROM meta ORDER BY key") { ($0.text(0), $0.text(1)) }
            meta = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        } catch let error as NavDataError {
            throw error
        } catch {
            throw .invalid("the file is not a navigation database (\(error))")
        }
        guard meta[NavDBSchema.MetaKey.schemaVersion.rawValue] == String(version) else {
            throw .invalid("schema version in table meta is not \(version)")
        }
        guard let cycleText = meta[NavDBSchema.MetaKey.cycle.rawValue], let cycle = AIRACCycle(ident: cycleText) else {
            throw .invalid("no valid AIRAC cycle in table meta")
        }
        guard let builderText = meta[NavDBSchema.MetaKey.builderVersion.rawValue], let builder = Int(builderText) else {
            throw .invalid("no builder version in table meta")
        }
        guard let sha = meta[NavDBSchema.MetaKey.sourceSHA256.rawValue], sha.count == 64 else {
            throw .invalid("no source SHA-256 in table meta")
        }
        return NavDataIdentity(cycle: cycle, schemaVersion: version, builderVersion: builder, sourceSHA256: sha)
    }

    /// Runs SQLite `quick_check`. Throws when the file is damaged.
    public func checkIntegrity() throws(NavDataError) {
        let result = try query { db throws(SQLiteError) in try db.rows("PRAGMA quick_check") { $0.text(0) } }
        guard result == ["ok"] else { throw .invalid("quick_check: \(result.prefix(3).joined(separator: "; "))") }
    }

    /// Runs a query on the connection. Low-level access for the converter checks.
    public func query<T: Sendable>(_ body: (SQLiteDatabase) throws(SQLiteError) -> T) throws(NavDataError) -> T {
        do {
            return try connection.withLock { db throws(SQLiteError) -> T in try body(db) }
        } catch {
            throw .storage(error.description)
        }
    }

    // MARK: NavDatabase

    public func airport(_ ident: String) throws(NavDataError) -> NavAirport? {
        try query { db throws(SQLiteError) in
            try db.rows("""
                SELECT \(Self.fixColumns), a.iata, a.name, a.elevation_ft, a.mag_var_deg, a.transition_altitude_ft,
                       a.transition_level_ft, a.longest_runway_ft, a.speed_limit_kt, a.speed_limit_altitude_ft
                FROM fix f JOIN airport a ON a.fix_id = f.id
                WHERE f.kind = 'airport' AND f.ident = ?
                ORDER BY f.id
                """, [.text(ident)]) { s in
                var r = RowReader(s)
                return NavAirport(fix: r.fix(), iata: r.optionalText(), name: r.text(), elevationFt: r.int(),
                                  magneticVariationDeg: r.optionalDouble(), transitionAltitudeFt: r.optionalInt(),
                                  transitionLevelFt: r.optionalInt(), longestRunwayFt: r.optionalInt(),
                                  speedLimitKt: r.optionalInt(), speedLimitAltitudeFt: r.optionalInt())
            }.first
        }
    }

    public func runways(airport: String) throws(NavDataError) -> [NavRunway] {
        try query { db throws(SQLiteError) in
            try db.rows("""
                SELECT \(Self.fixColumns), r.length_ft, r.width_ft, r.bearing_deg, r.bearing_true, r.threshold_elevation_ft,
                       r.displaced_threshold_ft, r.tch_ft, r.localizer, r.localizer_category
                FROM fix f JOIN runway r ON r.fix_id = f.id
                WHERE f.airport = ? AND f.kind = 'runway'
                ORDER BY f.ident, f.id
                """, [.text(airport)]) { s in
                var r = RowReader(s)
                return NavRunway(fix: r.fix(), lengthFt: r.int(), widthFt: r.optionalInt(), bearing: r.optionalCourse(),
                                 thresholdElevationFt: r.optionalInt(), displacedThresholdFt: r.optionalInt(),
                                 thresholdCrossingHeightFt: r.optionalInt(), localizerIdent: r.optionalText(),
                                 localizerCategory: r.optionalText())
            }
        }
    }

    public func localizers(airport: String) throws(NavDataError) -> [NavILS] {
        try query { db throws(SQLiteError) in
            try db.rows("""
                SELECT \(Self.fixColumns), i.category, i.frequency_mhz, i.runway, i.course_deg, i.course_true, i.gs_lat, i.gs_lon,
                       i.gs_angle_deg, i.loc_width_deg, i.declination_deg, i.gs_elevation_ft, i.gs_tch_ft
                FROM fix f JOIN ils i ON i.fix_id = f.id
                WHERE f.airport = ? AND f.kind = 'localizer'
                ORDER BY f.ident, f.id
                """, [.text(airport)]) { s in
                var r = RowReader(s)
                return NavILS(fix: r.fix(), category: r.text(), frequencyMHz: r.double(), runway: r.text(), course: r.course(),
                              glideSlopePosition: r.optionalPoint(), glideSlopeAngleDeg: r.optionalDouble(),
                              localizerWidthDeg: r.optionalDouble(), declinationDeg: r.optionalDouble(),
                              glideSlopeElevationFt: r.optionalInt(), glideSlopeHeightAtThresholdFt: r.optionalInt())
            }
        }
    }

    public func fixes(ident: String) throws(NavDataError) -> [NavFix] {
        try query { db throws(SQLiteError) in
            try db.rows("SELECT \(Self.fixColumns) FROM fix f WHERE f.ident = ? ORDER BY f.kind, f.region, f.airport, f.id",
                        [.text(ident)]) { s in
                var r = RowReader(s)
                return r.fix()
            }
        }
    }

    public func navaids(ident: String) throws(NavDataError) -> [NavNavaid] {
        try query { db throws(SQLiteError) in
            try db.rows("""
                SELECT \(Self.fixColumns), n.frequency, n.name, n.class, n.dme_lat, n.dme_lon, n.declination_deg,
                       n.elevation_ft, n.ils_dme_bias_nm
                FROM fix f JOIN navaid n ON n.fix_id = f.id
                WHERE f.ident = ?
                ORDER BY f.region, f.airport, f.id
                """, [.text(ident)]) { s in
                var r = RowReader(s)
                let fix = r.fix()
                return NavNavaid(fix: fix, type: fix.navaidType ?? .vor, frequency: r.double(), name: r.text(),
                                 navaidClass: r.text(), dmePosition: r.optionalPoint(), declinationDeg: r.optionalDouble(),
                                 elevationFt: r.optionalInt(), ilsDmeBiasNM: r.optionalDouble())
            }
        }
    }

    public func waypoints(ident: String) throws(NavDataError) -> [NavWaypoint] {
        try query { db throws(SQLiteError) in
            try db.rows("""
                SELECT \(Self.fixColumns), w.type, w.usage, w.name
                FROM fix f JOIN waypoint w ON w.fix_id = f.id
                WHERE f.ident = ?
                ORDER BY f.region, f.airport, f.id
                """, [.text(ident)]) { s in
                var r = RowReader(s)
                return NavWaypoint(fix: r.fix(), type: r.text(), usage: r.text(), name: r.text())
            }
        }
    }

    public func procedures(airport: String, kind: NavProcedureKind?) throws(NavDataError) -> [NavProcedure] {
        try query { db throws(SQLiteError) in
            var procedures = try db.rows("""
                SELECT id, airport, kind, ident, approach_type, runway FROM procedure
                WHERE airport = ? AND (?2 IS NULL OR kind = ?2)
                ORDER BY kind, ident
                """, [.text(airport), SQLiteValue(kind?.rawValue)]) { s in
                NavProcedure(id: s.int64(0), airport: s.text(1), kind: NavProcedureKind(rawValue: s.text(2)) ?? .approach,
                             ident: s.text(3), approachType: s.optionalText(4), runway: s.optionalText(5), transitions: [])
            }
            let transitions = try db.rows("""
                SELECT t.procedure_id, t.id, t.route_type, t.ident, t.role
                FROM procedure_transition t JOIN procedure p ON p.id = t.procedure_id
                WHERE p.airport = ? AND (?2 IS NULL OR p.kind = ?2)
                ORDER BY t.id
                """, [.text(airport), SQLiteValue(kind?.rawValue)]) { s in
                (s.int64(0), NavProcedureTransition(id: s.int64(1), routeType: s.text(2), ident: s.text(3),
                                                    role: NavTransitionRole(rawValue: s.text(4)) ?? .common))
            }
            var index: [Int64: Int] = [:]
            for (offset, procedure) in procedures.enumerated() { index[procedure.id] = offset }
            for (procedureID, transition) in transitions {
                if let offset = index[procedureID] { procedures[offset].transitions.append(transition) }
            }
            return procedures
        }
    }

    public func legs(transitionID: Int64) throws(NavDataError) -> [NavProcedureLeg] {
        try query { db throws(SQLiteError) in
            try db.rows("""
                SELECT l.seq, l.path_terminator,
                       l.fix_ident, l.fix_region, l.fix_code, \(Self.fixColumns("a")),
                       l.description, l.turn_direction, l.turn_direction_valid, l.fly_over, l.first_missed_leg,
                       l.nav_ident, l.nav_region, l.nav_code, \(Self.fixColumns("b")),
                       l.arc_radius_nm, l.theta_deg, l.rho_nm, l.course_deg, l.course_true, l.distance_nm, l.hold_time_min,
                       l.altitude_description, l.altitude1_ft, l.altitude2_ft, l.transition_altitude_ft,
                       l.speed_limit_kt, l.speed_description, l.vertical_angle_deg,
                       l.center_ident, l.center_region, l.center_code, \(Self.fixColumns("c")),
                       l.rnp_nm
                FROM procedure_leg l
                LEFT JOIN fix a ON a.id = l.fix_id
                LEFT JOIN fix b ON b.id = l.nav_id
                LEFT JOIN fix c ON c.id = l.center_id
                WHERE l.transition_id = ?
                ORDER BY l.seq
                """, [.integer(transitionID)]) { s in
                var r = RowReader(s)
                let sequence = r.int()
                let pathTerminator = r.text()
                let fix = r.fixRef()
                let description = r.text()
                let turnDirection = r.optionalText()
                let turnDirectionValid = r.bool()
                let flyOver = r.bool()
                let firstMissed = r.bool()
                let navaid = r.fixRef()
                let arcRadius = r.optionalDouble()
                let theta = r.optionalDouble()
                let rho = r.optionalDouble()
                let course = r.optionalCourse()
                let distance = r.optionalDouble()
                let holdTime = r.optionalDouble()
                let altitudeDescription = r.optionalText()
                let altitude1 = r.optionalInt()
                let altitude2 = r.optionalInt()
                let transitionAltitude = r.optionalInt()
                let speed = r.optionalInt()
                let speedDescription = r.optionalText()
                let verticalAngle = r.optionalDouble()
                let center = r.fixRef()
                let rnp = r.optionalDouble()
                return NavProcedureLeg(
                    sequence: sequence, pathTerminator: pathTerminator, fix: fix, descriptionCode: description,
                    turnDirection: turnDirection, turnDirectionValid: turnDirectionValid, isFlyOver: flyOver,
                    isFirstMissedApproachLeg: firstMissed, recommendedNavaid: navaid, arcRadiusNM: arcRadius,
                    thetaDeg: theta, rhoNM: rho, course: course, distanceNM: distance, holdTimeMinutes: holdTime,
                    altitudeDescription: altitudeDescription, altitude1Ft: altitude1, altitude2Ft: altitude2,
                    transitionAltitudeFt: transitionAltitude, speedLimitKt: speed, speedLimitDescription: speedDescription,
                    verticalAngleDeg: verticalAngle, centerFix: center, rnpNM: rnp)
            }
        }
    }

    public func airway(_ route: String) throws(NavDataError) -> [NavAirwayFix] {
        try query { db throws(SQLiteError) in
            try db.rows("""
                SELECT w.area, w.route, w.seq, w.fix_ident, w.fix_region, w.fix_code, \(Self.fixColumns("f")),
                       w.description, w.route_type, w.level, w.direction, w.outbound_course_deg, w.outbound_course_true,
                       w.inbound_course_deg, w.inbound_course_true, w.distance_nm, w.min_altitude_ft, w.max_altitude_ft
                FROM airway_fix w LEFT JOIN fix f ON f.id = w.fix_id
                WHERE w.route = ?
                ORDER BY w.area, w.seq, w.id
                """, [.text(route)]) { s in
                var r = RowReader(s)
                let area = r.text()
                let routeName = r.text()
                let sequence = r.int()
                let fix = r.fixRef() ?? NavFixRef(ident: "", region: "", code: "", fix: nil)
                return NavAirwayFix(area: area, route: routeName, sequence: sequence, fix: fix, descriptionCode: r.text(),
                                    routeType: r.text(), level: r.text(), directionRestriction: r.text(),
                                    outboundCourse: r.optionalCourse(), inboundCourse: r.optionalCourse(),
                                    distanceNM: r.optionalDouble(), minimumAltitudeFt: r.optionalInt(),
                                    maximumAltitudeFt: r.optionalInt())
            }
        }
    }

    public func fixes(near center: GeoPoint, radiusNM: Double, kinds: Set<NavFixKind>) throws(NavDataError) -> [NavFix] {
        let boxes = GeoBox.around(center, radiusNM: radiusNM)
        let candidates = try query { db throws(SQLiteError) in
            var result: [NavFix] = []
            for box in boxes {
                result += try db.rows("""
                    SELECT \(Self.fixColumns) FROM fix_rtree r JOIN fix f ON f.id = r.id
                    WHERE r.max_lat >= ? AND r.min_lat <= ? AND r.max_lon >= ? AND r.min_lon <= ?
                    """, [.real(box.minLat), .real(box.maxLat), .real(box.minLon), .real(box.maxLon)]) { s in
                    var r = RowReader(s)
                    return r.fix()
                }
            }
            return result
        }
        var seen = Set<Int64>()
        var inside: [(distance: Double, fix: NavFix)] = []
        for fix in candidates where kinds.isEmpty || kinds.contains(fix.kind) {
            guard seen.insert(fix.id).inserted else { continue }
            let distance = center.distanceNM(to: fix.position)
            if distance <= radiusNM { inside.append((distance, fix)) }
        }
        inside.sort { ($0.distance, $0.fix.id) < ($1.distance, $1.fix.id) }
        return inside.map(\.fix)
    }

    // MARK: Columns

    static let fixColumns = fixColumns("f")

    static func fixColumns(_ table: String) -> String {
        ["id", "kind", "ident", "region", "airport", "lat", "lon", "navaid_type"].map { "\(table).\($0)" }.joined(separator: ", ")
    }
}

/// Reads the columns of a row in order.
struct RowReader {
    let statement: SQLiteStatement
    var column: Int32 = 0

    init(_ statement: SQLiteStatement) {
        self.statement = statement
    }

    mutating func next() -> Int32 {
        defer { column += 1 }
        return column
    }

    mutating func int() -> Int { statement.int(next()) }
    mutating func int64() -> Int64 { statement.int64(next()) }
    mutating func optionalInt() -> Int? { statement.optionalInt(next()) }
    mutating func double() -> Double { statement.double(next()) }
    mutating func optionalDouble() -> Double? { statement.optionalDouble(next()) }
    mutating func text() -> String { statement.text(next()) }
    mutating func optionalText() -> String? { statement.optionalText(next()) }
    mutating func bool() -> Bool { statement.bool(next()) }

    mutating func course() -> NavCourse {
        NavCourse(degrees: double(), isTrue: bool())
    }

    mutating func optionalCourse() -> NavCourse? {
        let degrees = optionalDouble()
        let isTrue = bool()
        return degrees.map { NavCourse(degrees: $0, isTrue: isTrue) }
    }

    mutating func optionalPoint() -> GeoPoint? {
        let lat = optionalDouble()
        let lon = optionalDouble()
        guard let lat, let lon else { return nil }
        return GeoPoint(latDeg: lat, lonDeg: lon)
    }

    /// Reads the 8 columns of `NavDatabaseReader.fixColumns`.
    mutating func fix() -> NavFix {
        let id = int64()
        let kind = NavFixKind(rawValue: text()) ?? .waypoint
        let ident = text()
        let region = text()
        let airport = optionalText()
        let lat = double()
        let lon = double()
        let type = optionalText().flatMap(NavaidType.init(rawValue:))
        return NavFix(id: id, kind: kind, ident: ident, region: region, airport: airport,
                      position: GeoPoint(latDeg: lat, lonDeg: lon), navaidType: type)
    }

    /// Reads identifier, region, code and the 8 columns of a fix from a LEFT JOIN. Nil when the identifier is NULL.
    mutating func fixRef() -> NavFixRef? {
        let ident = optionalText()
        let region = optionalText()
        let code = optionalText()
        let fixIsNull = statement.isNull(column)
        let fix = self.fix()
        guard let ident else { return nil }
        return NavFixRef(ident: ident, region: region ?? "", code: code ?? "", fix: fixIsNull ? nil : fix)
    }
}
