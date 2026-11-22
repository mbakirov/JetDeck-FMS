import ARINC424
import CryptoKit
import Foundation
import Kernel
import NavDB
import SimCoreContract

public enum BuildError: Error, Sendable, CustomStringConvertible {
    case header(ARINC424Error)
    case cycle(String)
    case database(SQLiteError)
    case file(String)

    public var description: String {
        switch self {
        case .header(let error): "CIFP header is not valid: \(error)"
        case .cycle(let reason): "AIRAC cycle: \(reason)"
        case .database(let error): "database: \(error)"
        case .file(let reason): "file: \(reason)"
        }
    }
}

/// Converts a CIFP file (ARINC 424-18) into the navigation database (SQLite).
///
/// One input always gives the same database content: ids follow the order of lines in the source file,
/// and the database has no time of conversion.
public enum NavDBBuilder {
    /// Increase after each change of the conversion that can change the content of the database.
    ///
    /// History: 1 — first version. 2 — second localizer of a runway from columns 91-94; area of airways.
    public static let version = 2

    /// Number of errors and references that the report lists in full.
    static let listLimit = 200

    public static func build(cifp data: Data, sourceFileName: String, output: String,
                             filter: AirportFilter = AirportFilter()) throws(BuildError) -> BuildReport {
        let sourceSHA = sha256(data)
        let content: CIFPContent
        do {
            content = try CIFPFile.parse(data)
        } catch {
            throw .header(error)
        }
        guard let cycle = AIRACCycle(ident: content.header.cycle) else {
            throw .cycle("'\(content.header.cycle)' in HDR01 is not an AIRAC cycle")
        }
        var warnings: [String] = []
        if let date = content.header.effectiveDate {
            guard let effective = CalendarDate(year: date.year, month: date.month, day: date.day), effective == cycle.effective else {
                throw .cycle("the header gives the effective date \(date.year)-\(date.month)-\(date.day), cycle \(cycle.ident) starts on \(cycle.effective)")
            }
        } else {
            warnings.append("the header has no effective date; the date of cycle \(cycle.ident) is used")
        }
        if let stated = content.header.recordCount, stated != content.dataRecordCount {
            warnings.append("HDR01 states \(stated) records, the file has \(content.dataRecordCount)")
        }

        var plan = Plan(content: content, filter: filter)
        plan.make()

        let temporary = output + ".tmp"
        try? FileManager.default.removeItem(atPath: temporary)
        do {
            let db = try SQLiteDatabase(path: temporary, mode: .readWriteCreate)
            try write(plan, cycle: cycle, sourceFile: sourceFileName, sourceSHA: sourceSHA,
                      created: content.header.creationDate, to: db)
        } catch {
            try? FileManager.default.removeItem(atPath: temporary)
            throw .database(error)
        }
        do {
            if FileManager.default.fileExists(atPath: output) {
                try FileManager.default.removeItem(atPath: output)
            }
            try FileManager.default.moveItem(atPath: temporary, toPath: output)
        } catch {
            throw .file("cannot move the database to \(output): \(error.localizedDescription)")
        }
        guard let databaseData = FileManager.default.contents(atPath: output) else {
            throw .file("cannot read \(output)")
        }

        let errors = content.errors.map(\.description)
        return BuildReport(
            builderVersion: version,
            schemaVersion: NavDBSchema.version,
            source: .init(file: sourceFileName, sha256: sourceSHA, sizeBytes: data.count, lines: content.lineCount,
                          headerRecordCount: content.header.recordCount, dataRecords: content.dataRecordCount,
                          created: content.header.creationDate),
            cycle: .init(ident: cycle.ident, effective: cycle.effective, lastDay: cycle.lastDay),
            records: Dictionary(uniqueKeysWithValues: content.counts.map { ($0.key.rawValue, $0.value) }),
            skippedByDesign: content.skipped,
            errorCount: errors.count,
            errors: Array(errors.prefix(listLimit)),
            warnings: warnings,
            airportFilter: .init(minimumRunwayFt: filter.minimumRunwayFt, before: content.airports.count,
                                 after: plan.keptAirports.count, rejected: plan.rejected,
                                 rejectedShortRunway: plan.rejectedShortRunway),
            written: plan.written,
            unresolvedReferences: .init(count: plan.unresolved.count, byCode: plan.unresolvedByCode,
                                        samples: Array(plan.unresolved.prefix(listLimit))),
            duplicateLegs: plan.duplicateLegs,
            pathTerminators: plan.pathTerminators,
            approachTypes: plan.approachTypes,
            databaseSizeBytes: databaseData.count,
            databaseSHA256: sha256(databaseData)
        )
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Writing

    private static func write(_ plan: Plan, cycle: AIRACCycle, sourceFile: String, sourceSHA: String, created: String,
                              to db: SQLiteDatabase) throws(SQLiteError) {
        try db.execute("PRAGMA page_size = 4096; PRAGMA journal_mode = OFF; PRAGMA synchronous = OFF;")
        try db.execute(NavDBSchema.createSQL)
        try db.execute("BEGIN")

        let meta: [(NavDBSchema.MetaKey, String)] = [
            (.schemaVersion, String(NavDBSchema.version)),
            (.builderVersion, String(version)),
            (.cycle, cycle.ident),
            (.effective, cycle.effective.description),
            (.lastDay, cycle.lastDay.description),
            (.sourceFile, sourceFile),
            (.sourceSHA256, sourceSHA),
            (.sourceCreated, created),
        ]
        for (key, value) in meta {
            try db.run("INSERT INTO meta (key, value) VALUES (?, ?)", [.text(key.rawValue), .text(value)])
        }

        for source in plan.fixes {
            let id = plan.fixID[source.line]!
            try db.run("""
                INSERT INTO fix (id, kind, ident, region, airport, lat, lon, navaid_type, source_line)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.integer(id), .text(source.kind.rawValue), .text(source.ident), .text(source.region),
                      SQLiteValue(source.airport), .real(source.position.latitude), .real(source.position.longitude),
                      SQLiteValue(source.navaidType?.rawValue), .integer(Int64(source.line))])
            try db.run("INSERT INTO fix_rtree (id, min_lat, max_lat, min_lon, max_lon) VALUES (?, ?, ?, ?, ?)",
                       [.integer(id), .real(source.position.latitude), .real(source.position.latitude),
                        .real(source.position.longitude), .real(source.position.longitude)])
            try writeDetail(source.payload, id: id, to: db)
        }

        for fix in plan.airwayFixes {
            let r = fix.record
            try db.run("""
                INSERT INTO airway_fix (area, route, seq, fix_ident, fix_region, fix_code, fix_id, description, route_type, level,
                    direction, outbound_course_deg, outbound_course_true, inbound_course_deg, inbound_course_true,
                    distance_nm, min_altitude_ft, max_altitude_ft, source_line)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.text(r.area), .text(r.route), .integer(Int64(r.sequence)), .text(r.fix.ident), .text(r.fix.region), .text(r.fix.code),
                      SQLiteValue(fix.fixID), .text(r.descriptionCode), .text(String(r.routeType)), .text(trim(r.level)),
                      .text(trim(r.directionRestriction)), SQLiteValue(r.outboundCourse?.degrees),
                      SQLiteValue(r.outboundCourse.map { $0.isTrue }.map { $0 ? 1 : 0 } as Int?),
                      SQLiteValue(r.inboundCourse?.degrees), SQLiteValue(r.inboundCourse.map { $0.isTrue ? 1 : 0 } as Int?),
                      SQLiteValue(r.distanceNM), SQLiteValue(r.minimumAltitudeFt), SQLiteValue(r.maximumAltitudeFt),
                      .integer(Int64(r.line))])
        }

        for procedure in plan.procedures {
            try db.run("INSERT INTO procedure (id, airport, kind, ident, approach_type, runway) VALUES (?, ?, ?, ?, ?, ?)",
                       [.integer(procedure.id), .text(procedure.airport), .text(procedure.kind.rawValue), .text(procedure.ident),
                        SQLiteValue(procedure.approachType), SQLiteValue(procedure.runway)])
            for route in procedure.routes {
                try db.run("INSERT INTO procedure_transition (id, procedure_id, route_type, ident, role) VALUES (?, ?, ?, ?, ?)",
                           [.integer(route.id), .integer(procedure.id), .text(route.routeType), .text(route.ident),
                            .text(route.role.rawValue)])
                for leg in route.legs {
                    try writeLeg(leg, routeID: route.id, to: db)
                }
            }
        }

        try db.execute("COMMIT")
        try db.execute("PRAGMA user_version = \(NavDBSchema.version)")
        try db.execute("VACUUM")
    }

    private static func writeDetail(_ payload: FixPayload, id: Int64, to db: SQLiteDatabase) throws(SQLiteError) {
        switch payload {
        case .airport(let r):
            try db.run("""
                INSERT INTO airport (fix_id, area, iata, name, elevation_ft, mag_var_deg, transition_altitude_ft,
                    transition_level_ft, longest_runway_ft, longest_runway_surface, ifr, speed_limit_kt,
                    speed_limit_altitude_ft, public_military)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.integer(id), .text(r.area), SQLiteValue(r.iata), .text(r.name), .integer(Int64(r.elevationFt)),
                      SQLiteValue(r.magneticVariation), SQLiteValue(r.transitionAltitudeFt), SQLiteValue(r.transitionLevelFt),
                      SQLiteValue(r.longestRunwayFt), .text(String(r.longestRunwaySurface)), SQLiteValue(r.ifrCapable),
                      SQLiteValue(r.speedLimitKt), SQLiteValue(r.speedLimitAltitudeFt), .text(String(r.publicMilitary))])
        case .runway(let r):
            try db.run("""
                INSERT INTO runway (fix_id, length_ft, width_ft, bearing_deg, bearing_true, threshold_elevation_ft,
                    displaced_threshold_ft, tch_ft, localizer, localizer_category, second_localizer)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.integer(id), .integer(Int64(r.lengthFt)), SQLiteValue(r.widthFt), SQLiteValue(r.bearing?.degrees),
                      SQLiteValue(r.bearing.map { $0.isTrue ? 1 : 0 } as Int?), SQLiteValue(r.thresholdElevationFt), SQLiteValue(r.displacedThresholdFt),
                      SQLiteValue(r.thresholdCrossingHeightFt), SQLiteValue(r.localizer),
                      SQLiteValue(r.localizerCategory.map(String.init)), SQLiteValue(r.secondLocalizer)])
        case .localizer(let r):
            try db.run("""
                INSERT INTO ils (fix_id, category, frequency_mhz, runway, course_deg, course_true, gs_lat, gs_lon,
                    gs_angle_deg, loc_width_deg, declination_deg, gs_elevation_ft, gs_tch_ft)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.integer(id), .text(String(r.category)), .real(r.frequencyMHz), .text(r.runway),
                      .real(r.localizerBearing.degrees), SQLiteValue(r.localizerBearing.isTrue),
                      SQLiteValue(r.glideSlopePosition?.latitude), SQLiteValue(r.glideSlopePosition?.longitude),
                      SQLiteValue(r.glideSlopeAngleDeg), SQLiteValue(r.localizerWidthDeg), SQLiteValue(r.stationDeclination),
                      SQLiteValue(r.glideSlopeElevationFt), SQLiteValue(r.glideSlopeHeightAtThresholdFt)])
        case .vhf(let r):
            // The DME position is written only when it is not the VOR position.
            let separateDME = r.vorPosition != nil && r.dmePosition != nil && r.dmePosition != r.vorPosition
            try db.run("""
                INSERT INTO navaid (fix_id, frequency, class, name, dme_ident, dme_lat, dme_lon, declination_deg,
                    elevation_ft, ils_dme_bias_nm)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [.integer(id), .real(r.frequencyMHz), .text(r.navaidClass), .text(r.name), SQLiteValue(r.dmeIdent),
                      SQLiteValue(separateDME ? r.dmePosition?.latitude : nil),
                      SQLiteValue(separateDME ? r.dmePosition?.longitude : nil),
                      SQLiteValue(r.stationDeclination), SQLiteValue(r.dmeElevationFt), SQLiteValue(r.ilsDmeBiasNM)])
        case .ndb(let r):
            try db.run("""
                INSERT INTO navaid (fix_id, frequency, class, name, declination_deg) VALUES (?, ?, ?, ?, ?)
                """, [.integer(id), .real(r.frequencyKHz), .text(r.navaidClass), .text(r.name), SQLiteValue(r.magneticVariation)])
        case .waypoint(let r):
            try db.run("INSERT INTO waypoint (fix_id, type, usage, name) VALUES (?, ?, ?, ?)",
                       [.integer(id), .text(r.type), .text(r.usage), .text(r.name)])
        }
    }

    private static func writeLeg(_ leg: Plan.Leg, routeID: Int64, to db: SQLiteDatabase) throws(SQLiteError) {
        let r = leg.record
        var distance: Double?
        var holdTime: Double?
        switch r.distanceOrTime {
        case .nauticalMiles(let value)?: distance = value
        case .minutes(let value)?: holdTime = value
        case nil: break
        }
        try db.run("""
            INSERT INTO procedure_leg (transition_id, seq, path_terminator, fix_ident, fix_region, fix_code, fix_id,
                description, turn_direction, turn_direction_valid, fly_over, first_missed_leg, rnp_nm,
                nav_ident, nav_region, nav_code, nav_id, arc_radius_nm, theta_deg, rho_nm, course_deg, course_true,
                distance_nm, hold_time_min, altitude_description, altitude1_ft, altitude2_ft, transition_altitude_ft,
                speed_limit_kt, speed_description, vertical_angle_deg, center_ident, center_region, center_code, center_id,
                source_line)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.integer(routeID), .integer(Int64(r.sequence)), .text(r.pathTerminator),
                  SQLiteValue(r.fix?.ident), SQLiteValue(r.fix?.region), SQLiteValue(r.fix?.code), SQLiteValue(leg.fixID),
                  .text(r.descriptionCode), SQLiteValue(r.turnDirection.map(String.init)), SQLiteValue(r.turnDirectionValid),
                  SQLiteValue(r.isFlyOver), SQLiteValue(r.isFirstMissedApproachLeg), SQLiteValue(r.rnpNM),
                  SQLiteValue(r.recommendedNavaid?.ident), SQLiteValue(r.recommendedNavaid?.region),
                  SQLiteValue(r.recommendedNavaid?.code), SQLiteValue(leg.navaidID),
                  SQLiteValue(r.arcRadiusNM), SQLiteValue(r.thetaDeg), SQLiteValue(r.rhoNM),
                  SQLiteValue(r.course?.degrees), SQLiteValue(r.course.map { $0.isTrue ? 1 : 0 } as Int?),
                  SQLiteValue(distance), SQLiteValue(holdTime), SQLiteValue(r.altitudeDescription.map(String.init)),
                  SQLiteValue(r.altitude1Ft), SQLiteValue(r.altitude2Ft), SQLiteValue(r.transitionAltitudeFt),
                  SQLiteValue(r.speedLimitKt), SQLiteValue(r.speedLimitDescription.map(String.init)),
                  SQLiteValue(r.verticalAngleDeg), SQLiteValue(r.centerFix?.ident), SQLiteValue(r.centerFix?.region),
                  SQLiteValue(r.centerFix?.code), SQLiteValue(leg.centerID), .integer(Int64(r.line))])
    }

    private static func trim(_ c: Character) -> String {
        c == " " ? "" : String(c)
    }
}
