import Foundation

/// The schema of the navigation database file.
///
/// Increase `version` after each change of the tables. The reader rejects a file with another version.
/// The application then uses the database from the application bundle until a file with the new version is loaded.
public enum NavDBSchema {
    ///
    /// History: 1 — first version. 2 — `airway_fix.area`.
    public static let version = 2

    /// Keys of the table `meta`.
    public enum MetaKey: String, CaseIterable {
        case schemaVersion = "schema_version"
        case builderVersion = "builder_version"
        case cycle
        case effective
        case lastDay = "last_day"
        case sourceFile = "source_file"
        case sourceSHA256 = "source_sha256"
        case sourceCreated = "source_created"
    }

    /// SQL that makes all tables. Coordinates are in degrees (north and east positive).
    /// Courses: `*_deg` and `*_true` (1 for a true course). Altitudes in feet, distances in nautical miles.
    public static let createSQL = """
    CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    ) WITHOUT ROWID;

    -- All points: airports, runway thresholds, localizers, navaids, waypoints.
    CREATE TABLE fix (
        id INTEGER PRIMARY KEY,
        kind TEXT NOT NULL,            -- airport, runway, localizer, vhfNavaid, ndb, waypoint
        ident TEXT NOT NULL,
        region TEXT NOT NULL,          -- ICAO code
        airport TEXT,                  -- airport of a terminal point; NULL for an en route point
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        navaid_type TEXT,              -- vor, vorDme, vortac, tacan, dme, ilsDme, ndb, locator
        source_line INTEGER NOT NULL   -- line in the source file
    );
    CREATE INDEX fix_ident ON fix(ident);
    CREATE INDEX fix_airport ON fix(airport, kind);

    -- Spatial index for the map of the ND.
    CREATE VIRTUAL TABLE fix_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);

    CREATE TABLE airport (
        fix_id INTEGER PRIMARY KEY REFERENCES fix(id),
        area TEXT NOT NULL,
        iata TEXT,
        name TEXT NOT NULL,
        elevation_ft INTEGER NOT NULL,
        mag_var_deg REAL,
        transition_altitude_ft INTEGER,
        transition_level_ft INTEGER,
        longest_runway_ft INTEGER,
        longest_runway_surface TEXT NOT NULL,
        ifr INTEGER NOT NULL,
        speed_limit_kt INTEGER,
        speed_limit_altitude_ft INTEGER,
        public_military TEXT NOT NULL
    );

    CREATE TABLE runway (
        fix_id INTEGER PRIMARY KEY REFERENCES fix(id),
        length_ft INTEGER NOT NULL,
        width_ft INTEGER,
        bearing_deg REAL,
        bearing_true INTEGER,
        threshold_elevation_ft INTEGER,
        displaced_threshold_ft INTEGER,
        tch_ft INTEGER,
        localizer TEXT,
        localizer_category TEXT,
        second_localizer TEXT
    );

    CREATE TABLE ils (
        fix_id INTEGER PRIMARY KEY REFERENCES fix(id),
        category TEXT NOT NULL,
        frequency_mhz REAL NOT NULL,
        runway TEXT NOT NULL,
        course_deg REAL NOT NULL,
        course_true INTEGER NOT NULL,
        gs_lat REAL,
        gs_lon REAL,
        gs_angle_deg REAL,
        loc_width_deg REAL,
        declination_deg REAL,
        gs_elevation_ft INTEGER,
        gs_tch_ft INTEGER
    );

    CREATE TABLE navaid (
        fix_id INTEGER PRIMARY KEY REFERENCES fix(id),
        frequency REAL NOT NULL,       -- MHz for VHF, kHz for NDB
        class TEXT NOT NULL,
        name TEXT NOT NULL,
        dme_ident TEXT,
        dme_lat REAL,
        dme_lon REAL,
        declination_deg REAL,
        elevation_ft INTEGER,
        ils_dme_bias_nm REAL
    );

    CREATE TABLE waypoint (
        fix_id INTEGER PRIMARY KEY REFERENCES fix(id),
        type TEXT NOT NULL,
        usage TEXT NOT NULL,
        name TEXT NOT NULL
    );

    CREATE TABLE airway_fix (
        id INTEGER PRIMARY KEY,
        area TEXT NOT NULL,            -- ARINC 424 area code: USA, CAN, PAC, LAM
        route TEXT NOT NULL,
        seq INTEGER NOT NULL,
        fix_ident TEXT NOT NULL,
        fix_region TEXT NOT NULL,
        fix_code TEXT NOT NULL,
        fix_id INTEGER REFERENCES fix(id),
        description TEXT NOT NULL,
        route_type TEXT NOT NULL,
        level TEXT NOT NULL,
        direction TEXT NOT NULL,
        outbound_course_deg REAL,
        outbound_course_true INTEGER,
        inbound_course_deg REAL,
        inbound_course_true INTEGER,
        distance_nm REAL,
        min_altitude_ft INTEGER,
        max_altitude_ft INTEGER,
        source_line INTEGER NOT NULL
    );
    CREATE INDEX airway_fix_route ON airway_fix(route, area, seq);

    CREATE TABLE procedure (
        id INTEGER PRIMARY KEY,
        airport TEXT NOT NULL,
        kind TEXT NOT NULL,            -- SID, STAR, APPROACH
        ident TEXT NOT NULL,
        approach_type TEXT,            -- route type of the final approach
        runway TEXT                    -- runway of an approach, NULL for circling
    );
    CREATE UNIQUE INDEX procedure_key ON procedure(airport, kind, ident);

    -- One route of a procedure: a transition, the common route or the final approach.
    CREATE TABLE procedure_transition (
        id INTEGER PRIMARY KEY,
        procedure_id INTEGER NOT NULL REFERENCES procedure(id),
        route_type TEXT NOT NULL,
        ident TEXT NOT NULL,
        role TEXT NOT NULL             -- runwayTransition, common, enrouteTransition, approachTransition, final
    );
    CREATE INDEX procedure_transition_procedure ON procedure_transition(procedure_id);

    CREATE TABLE procedure_leg (
        transition_id INTEGER NOT NULL REFERENCES procedure_transition(id),
        seq INTEGER NOT NULL,
        path_terminator TEXT NOT NULL,
        fix_ident TEXT,
        fix_region TEXT,
        fix_code TEXT,
        fix_id INTEGER REFERENCES fix(id),
        description TEXT NOT NULL,
        turn_direction TEXT,
        turn_direction_valid INTEGER NOT NULL,
        fly_over INTEGER NOT NULL,
        first_missed_leg INTEGER NOT NULL,
        rnp_nm REAL,
        nav_ident TEXT,
        nav_region TEXT,
        nav_code TEXT,
        nav_id INTEGER REFERENCES fix(id),
        arc_radius_nm REAL,
        theta_deg REAL,
        rho_nm REAL,
        course_deg REAL,
        course_true INTEGER,
        distance_nm REAL,
        hold_time_min REAL,
        altitude_description TEXT,
        altitude1_ft INTEGER,
        altitude2_ft INTEGER,
        transition_altitude_ft INTEGER,
        speed_limit_kt INTEGER,
        speed_description TEXT,
        vertical_angle_deg REAL,
        center_ident TEXT,
        center_region TEXT,
        center_code TEXT,
        center_id INTEGER REFERENCES fix(id),
        source_line INTEGER NOT NULL,
        PRIMARY KEY (transition_id, seq)
    ) WITHOUT ROWID;
    """
}
