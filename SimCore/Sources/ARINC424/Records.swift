import Foundation

// Record layouts of ARINC 424-18, the version of the FAA CIFP file (FAACIFP18).
// Each initialiser reads a primary record and throws ARINC424Error when a field is not valid.

/// A reference from one record to a fix in another record (identifier, ICAO code, section, subsection).
public struct FixReference: Sendable, Equatable, Hashable {
    public var ident: String
    public var region: String
    /// Section and subsection of the referenced record, for example `PC`, `EA`, `D`, `DB`, `PG`, `PI`.
    public var code: String

    public init(ident: String, region: String, code: String) {
        self.ident = ident
        self.region = region
        self.code = code
    }

    /// Reads a reference. Returns nil when the identifier is blank.
    static func read(_ line: ARINC424Line, ident: ClosedRange<Int>, region: ClosedRange<Int>, section: Int, subsection: Int) -> FixReference? {
        guard let id = line.optionalText(ident) else { return nil }
        let s = line.character(section)
        let sub = line.character(subsection)
        let code: String
        switch (s, sub) {
        case (" ", _): code = ""
        case (_, " "): code = String(s)
        default: code = String([s, sub])
        }
        return FixReference(ident: id, region: line.text(region), code: code)
    }
}

/// Airport (section P, subsection A).
public struct AirportRecord: Sendable, Equatable {
    public var line: Int
    /// Customer or area code, for example `USA`, `CAN`, `PAC`, `LAM`.
    public var area: String
    public var ident: String
    public var region: String
    public var iata: String?
    public var speedLimitAltitudeFt: Int?
    /// Length of the longest runway in feet. The file gives hundreds of feet.
    public var longestRunwayFt: Int?
    public var ifrCapable: Bool
    /// Surface of the longest runway: `H` hard, `S` soft, `W` water, `U` undefined.
    public var longestRunwaySurface: Character
    public var position: ARINC424Coordinate
    public var magneticVariation: Double?
    public var elevationFt: Int
    public var speedLimitKt: Int?
    public var transitionAltitudeFt: Int?
    public var transitionLevelFt: Int?
    /// `C` civil, `M` military, `P` private, `J` joint.
    public var publicMilitary: Character
    public var datum: String
    public var name: String

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        area = line.text(2...4)
        ident = line.text(7...10)
        region = line.text(11...12)
        iata = line.optionalText(14...16)
        speedLimitAltitudeFt = try line.altitude("speed limit altitude", 23...27)
        longestRunwayFt = try line.integer("longest runway", 28...30).map { $0 * 100 }
        ifrCapable = line.character(31) == "Y"
        longestRunwaySurface = line.character(32)
        position = try line.requiredCoordinate("airport reference point", latitude: 33...41, longitude: 42...51)
        magneticVariation = try line.magneticVariation("magnetic variation", 52...56)
        elevationFt = try line.requiredInteger("airport elevation", 57...61)
        speedLimitKt = try line.integer("speed limit", 62...64)
        transitionAltitudeFt = try line.integer("transition altitude", 71...75)
        transitionLevelFt = try line.integer("transition level", 76...80)
        publicMilitary = line.character(81)
        datum = line.text(87...89)
        name = line.text(94...123)
        guard !ident.isEmpty else { throw line.error("airport identifier", 7...10, "the identifier is blank") }
    }
}

/// Runway (section P, subsection G).
public struct RunwayRecord: Sendable, Equatable {
    public var line: Int
    public var airport: String
    public var airportRegion: String
    /// Identifier with the prefix, for example `RW04L`. Some water runways have other identifiers.
    public var ident: String
    public var lengthFt: Int
    /// Nil for a few small airports that have no bearing in the file.
    public var bearing: ARINC424Bearing?
    /// Position of the landing threshold.
    public var threshold: ARINC424Coordinate
    public var thresholdElevationFt: Int?
    public var displacedThresholdFt: Int?
    public var thresholdCrossingHeightFt: Int?
    public var widthFt: Int?
    /// Identifier of the ILS, MLS or GLS for this runway.
    public var localizer: String?
    /// Category of this localizer (`0`, `1`, `2`, `3`, `I`, `L`, `A`, `S`, `F`).
    public var localizerCategory: Character?
    public var secondLocalizer: String?
    public var description: String?

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        airport = line.text(7...10)
        airportRegion = line.text(11...12)
        ident = line.text(14...18)
        lengthFt = try line.requiredInteger("runway length", 23...27)
        bearing = try line.bearing("runway magnetic bearing", 28...31)
        threshold = try line.requiredCoordinate("runway threshold", latitude: 33...41, longitude: 42...51)
        thresholdElevationFt = try line.integer("landing threshold elevation", 67...71)
        displacedThresholdFt = try line.integer("displaced threshold distance", 72...75)
        thresholdCrossingHeightFt = try line.integer("threshold crossing height", 76...77)
        widthFt = try line.integer("runway width", 78...80)
        localizer = line.optionalText(82...85)
        localizerCategory = line.isBlank(86...86) ? nil : line.character(86)
        secondLocalizer = line.optionalText(89...92)
        description = line.optionalText(102...123)
        // A water runway can have an identifier without the prefix RW, for example `E` or `W`.
        guard !ident.isEmpty else { throw line.error("runway identifier", 14...18, "the identifier is blank") }
    }
}

/// Localizer and glide slope of an ILS, LDA, SDF or IGS (section P, subsection I).
public struct LocalizerRecord: Sendable, Equatable {
    public var line: Int
    public var airport: String
    public var airportRegion: String
    public var ident: String
    /// `0` ILS localizer only, `1` `2` `3` ILS category, `I` IGS, `L` LDA with glide slope,
    /// `A` LDA without glide slope, `S` SDF with glide slope, `F` SDF without glide slope.
    public var category: Character
    public var frequencyMHz: Double
    public var runway: String
    public var localizerPosition: ARINC424Coordinate
    public var localizerBearing: ARINC424Bearing
    public var glideSlopePosition: ARINC424Coordinate?
    /// Distance from the localizer antenna to the runway end in feet.
    public var localizerPositionFt: Int?
    public var glideSlopePositionFt: Int?
    /// Course width in degrees.
    public var localizerWidthDeg: Double?
    public var glideSlopeAngleDeg: Double?
    public var stationDeclination: Double?
    public var glideSlopeHeightAtThresholdFt: Int?
    public var glideSlopeElevationFt: Int?

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        airport = line.text(7...10)
        airportRegion = line.text(11...12)
        ident = line.text(14...17)
        category = line.character(18)
        guard let frequency = try line.decimal("localizer frequency", 23...27, scale: 2) else {
            throw line.error("localizer frequency", 23...27, "the field is blank")
        }
        frequencyMHz = frequency
        runway = line.text(28...32)
        localizerPosition = try line.requiredCoordinate("localizer", latitude: 33...41, longitude: 42...51)
        guard let bearing = try line.bearing("localizer bearing", 52...55) else {
            throw line.error("localizer bearing", 52...55, "the field is blank")
        }
        localizerBearing = bearing
        glideSlopePosition = try line.coordinate("glide slope", latitude: 56...64, longitude: 65...74)
        localizerPositionFt = try line.integer("localizer position", 75...78)
        glideSlopePositionFt = try line.integer("glide slope position", 80...83)
        localizerWidthDeg = try line.decimal("localizer width", 84...87, scale: 2)
        glideSlopeAngleDeg = try line.decimal("glide slope angle", 88...90, scale: 2)
        stationDeclination = try line.magneticVariation("station declination", 91...95)
        glideSlopeHeightAtThresholdFt = try line.integer("glide slope height at threshold", 96...97)
        glideSlopeElevationFt = try line.integer("glide slope elevation", 98...102)
    }

    /// True for an ILS with a glide slope (categories 1, 2 and 3).
    public var isILSWithGlideSlope: Bool {
        category == "1" || category == "2" || category == "3"
    }
}

/// VHF navaid: VOR, VOR/DME, VORTAC, TACAN, DME, ILS/DME (section D, subsection blank).
public struct VHFNavaidRecord: Sendable, Equatable {
    public var line: Int
    /// Airport for a terminal facility, for example an ILS/DME. Nil for an en route facility.
    public var airport: String?
    public var ident: String
    public var region: String
    public var frequencyMHz: Double
    /// Navaid class, 5 columns. Column 1: `V` VOR. Column 2: `D` DME, `T` TACAN, `M` military TACAN, `I` ILS/DME,
    /// `N` MLS/DME (N), `P` MLS/DME (P). Column 3: power `T`, `L`, `H`, `U`, `C`.
    public var navaidClass: String
    public var vorPosition: ARINC424Coordinate?
    public var dmeIdent: String?
    public var dmePosition: ARINC424Coordinate?
    public var stationDeclination: Double?
    public var dmeElevationFt: Int?
    public var ilsDmeBiasNM: Double?
    public var datum: String
    public var name: String

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        airport = line.optionalText(7...10)
        ident = line.text(14...17)
        region = line.text(20...21)
        guard let frequency = try line.decimal("VOR frequency", 23...27, scale: 2) else {
            throw line.error("VOR frequency", 23...27, "the field is blank")
        }
        frequencyMHz = frequency
        navaidClass = line.raw(28...32)
        vorPosition = try line.coordinate("VOR", latitude: 33...41, longitude: 42...51)
        dmeIdent = line.optionalText(52...55)
        dmePosition = try line.coordinate("DME", latitude: 56...64, longitude: 65...74)
        stationDeclination = try line.magneticVariation("station declination", 75...79)
        dmeElevationFt = try line.integer("DME elevation", 80...84)
        ilsDmeBiasNM = try line.decimal("ILS/DME bias", 86...87, scale: 1)
        datum = line.text(91...93)
        name = line.text(94...123)
        guard vorPosition != nil || dmePosition != nil else {
            throw line.error("VOR and DME position", 33...74, "the record has no position")
        }
    }

    /// The position of the VOR, or of the DME when there is no VOR.
    public var position: ARINC424Coordinate {
        vorPosition ?? dmePosition!
    }
}

/// NDB: en route (section D, subsection B) or terminal (section P, subsection N).
public struct NDBRecord: Sendable, Equatable {
    public var line: Int
    /// Airport for a terminal NDB. Nil for an en route NDB.
    public var airport: String?
    public var ident: String
    public var region: String
    public var frequencyKHz: Double
    /// NDB class, 5 columns. Column 1: `H` NDB, `S` SABH, `M` marine beacon. Column 2: `I` inner, `M` middle,
    /// `O` outer, `C` back marker (locator). Column 3: power.
    public var navaidClass: String
    public var position: ARINC424Coordinate
    public var magneticVariation: Double?
    public var datum: String
    public var name: String

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        airport = line.optionalText(7...10)
        ident = line.text(14...17)
        region = line.text(20...21)
        guard let frequency = try line.decimal("NDB frequency", 23...27, scale: 1) else {
            throw line.error("NDB frequency", 23...27, "the field is blank")
        }
        frequencyKHz = frequency
        navaidClass = line.raw(28...32)
        position = try line.requiredCoordinate("NDB", latitude: 33...41, longitude: 42...51)
        magneticVariation = try line.magneticVariation("magnetic variation", 75...79)
        datum = line.text(91...93)
        name = line.text(94...123)
    }
}

/// Waypoint: en route (section E, subsection A) or terminal (section P, subsection C).
public struct WaypointRecord: Sendable, Equatable {
    public var line: Int
    /// Airport for a terminal waypoint. Nil for an en route waypoint (region code `ENRT`).
    public var airport: String?
    public var ident: String
    public var region: String
    /// Waypoint type, 3 columns, for example `W  ` (named), `C  ` (named intersection), `R  ` (unnamed).
    public var type: String
    /// Waypoint usage, 2 columns. Column 2: `H` high, `L` low, `B` both, blank terminal.
    public var usage: String
    public var position: ARINC424Coordinate
    public var magneticVariation: Double?
    public var datum: String
    public var name: String

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        let regionCode = line.text(7...10)
        airport = regionCode == "ENRT" || regionCode.isEmpty ? nil : regionCode
        ident = line.text(14...18)
        region = line.text(20...21)
        type = line.raw(27...29)
        usage = line.raw(30...31)
        position = try line.requiredCoordinate("waypoint", latitude: 33...41, longitude: 42...51)
        magneticVariation = try line.magneticVariation("dynamic magnetic variation", 75...79)
        datum = line.text(85...87)
        name = line.text(99...123)
        guard !ident.isEmpty else { throw line.error("waypoint identifier", 14...18, "the identifier is blank") }
    }
}

/// One fix of an en route airway (section E, subsection R).
public struct AirwayFixRecord: Sendable, Equatable {
    public var line: Int
    public var route: String
    public var sequence: Int
    public var fix: FixReference
    /// Waypoint description code, 4 columns.
    public var descriptionCode: String
    /// `A` airline, `C` control, `D` direct, `H` helicopter, `O` officially designated, `R` RNAV, `S` undesignated.
    public var routeType: Character
    /// `B` all altitudes, `H` high, `L` low.
    public var level: Character
    /// `F` forward only, `B` backward only, blank both directions.
    public var directionRestriction: Character
    public var outboundCourse: ARINC424Bearing?
    public var distanceNM: Double?
    public var inboundCourse: ARINC424Bearing?
    public var minimumAltitudeFt: Int?
    public var minimumAltitude2Ft: Int?
    public var maximumAltitudeFt: Int?

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        route = line.text(14...18)
        sequence = try line.requiredInteger("sequence number", 26...29)
        guard let fix = FixReference.read(line, ident: 30...34, region: 35...36, section: 37, subsection: 38) else {
            throw line.error("fix identifier", 30...34, "the identifier is blank")
        }
        self.fix = fix
        descriptionCode = line.raw(40...43)
        routeType = line.character(45)
        level = line.character(46)
        directionRestriction = line.character(47)
        outboundCourse = try line.bearing("outbound course", 71...74)
        distanceNM = try line.decimal("route distance", 75...78, scale: 1)
        inboundCourse = try line.bearing("inbound course", 79...82)
        minimumAltitudeFt = try Self.altitude(line, "minimum altitude", 84...88)
        minimumAltitude2Ft = try Self.altitude(line, "minimum altitude 2", 89...93)
        maximumAltitudeFt = try Self.altitude(line, "maximum altitude", 94...98)
        guard !route.isEmpty else { throw line.error("route identifier", 14...18, "the identifier is blank") }
    }

    /// `UNKNN` means that the altitude is not known, `NESTB` that it is not established. Both are nil.
    static func altitude(_ line: ARINC424Line, _ field: String, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> Int? {
        let value = line.text(columns)
        if value == "UNKNN" || value == "NESTB" { return nil }
        return try line.altitude(field, columns)
    }
}

/// The kind of a terminal procedure.
public enum ProcedureKind: String, Sendable, Codable, CaseIterable {
    case sid = "SID"
    case star = "STAR"
    case approach = "APPROACH"
}

/// One leg of a SID (PD), STAR (PE) or approach (PF).
public struct ProcedureLegRecord: Sendable, Equatable {
    public var line: Int
    public var kind: ProcedureKind
    public var airport: String
    public var airportRegion: String
    public var procedure: String
    /// Route type, for example SID `2` common route, STAR `4` RNAV en route transition, approach `I` ILS, `A` transition.
    public var routeType: Character
    /// Transition identifier. Blank for a common route and for the final approach.
    public var transition: String
    public var sequence: Int
    public var fix: FixReference?
    /// Waypoint description code, 4 columns.
    public var descriptionCode: String
    /// `L` left, `R` right, `E` either.
    public var turnDirection: Character?
    public var rnpNM: Double?
    /// Path and terminator, for example `IF`, `TF`, `CF`, `RF`.
    public var pathTerminator: String
    public var turnDirectionValid: Bool
    public var recommendedNavaid: FixReference?
    /// Radius of an RF leg in nautical miles.
    public var arcRadiusNM: Double?
    public var thetaDeg: Double?
    public var rhoNM: Double?
    public var course: ARINC424Bearing?
    public var distanceOrTime: ARINC424DistanceOrTime?
    /// Altitude description, for example `+` at or above, `-` at or below, `B` between, blank at.
    public var altitudeDescription: Character?
    public var altitude1Ft: Int?
    public var altitude2Ft: Int?
    public var transitionAltitudeFt: Int?
    public var speedLimitKt: Int?
    /// `+` at or above, `-` at or below, blank or `@` at.
    public var speedLimitDescription: Character?
    /// Vertical angle in degrees. Negative for a descent.
    public var verticalAngleDeg: Double?
    /// Center fix of an RF or AF leg.
    public var centerFix: FixReference?
    public var routeQualifier1: Character?
    public var routeQualifier2: Character?

    public init(_ line: ARINC424Line) throws(ARINC424Error) {
        self.line = line.number
        switch line.character(13) {
        case "D": kind = .sid
        case "E": kind = .star
        case "F": kind = .approach
        default: throw line.error("subsection", 13...13, "not a procedure")
        }
        airport = line.text(7...10)
        airportRegion = line.text(11...12)
        procedure = line.text(14...19)
        routeType = line.character(20)
        transition = line.text(21...25)
        sequence = try line.requiredInteger("sequence number", 27...29)
        fix = FixReference.read(line, ident: 30...34, region: 35...36, section: 37, subsection: 38)
        descriptionCode = line.raw(40...43)
        turnDirection = Self.optionalCharacter(line, 44)
        rnpNM = try Self.rnp(line, 45...47)
        pathTerminator = line.text(48...49)
        turnDirectionValid = line.character(50) == "Y"
        recommendedNavaid = FixReference.read(line, ident: 51...54, region: 55...56, section: 79, subsection: 80)
        arcRadiusNM = try line.decimal("arc radius", 57...62, scale: 3)
        thetaDeg = try line.decimal("theta", 63...66, scale: 1)
        rhoNM = try line.decimal("rho", 67...70, scale: 1)
        course = try line.bearing("magnetic course", 71...74)
        distanceOrTime = try line.distanceOrTime("route distance or time", 75...78)
        altitudeDescription = Self.optionalCharacter(line, 83)
        altitude1Ft = try line.altitude("altitude 1", 85...89)
        altitude2Ft = try line.altitude("altitude 2", 90...94)
        transitionAltitudeFt = try line.integer("transition altitude", 95...99)
        speedLimitKt = try line.integer("speed limit", 100...102)
        verticalAngleDeg = try line.decimal("vertical angle", 103...106, scale: 2)
        centerFix = FixReference.read(line, ident: 107...111, region: 113...114, section: 115, subsection: 116)
        speedLimitDescription = Self.optionalCharacter(line, 118)
        routeQualifier1 = Self.optionalCharacter(line, 119)
        routeQualifier2 = Self.optionalCharacter(line, 120)
        guard pathTerminator.count == 2 else { throw line.error("path and termination", 48...49, "the field is blank") }
        guard !procedure.isEmpty else { throw line.error("procedure identifier", 14...19, "the identifier is blank") }
    }

    static func optionalCharacter(_ line: ARINC424Line, _ column: Int) -> Character? {
        let c = line.character(column)
        return c == " " ? nil : c
    }

    /// RNP: two digits and a negative exponent, `010` = 1.0, `031` = 0.3 (ARINC 424 section 5.211).
    static func rnp(_ line: ARINC424Line, _ columns: ClosedRange<Int>) throws(ARINC424Error) -> Double? {
        if line.isBlank(columns) { return nil }
        guard let mantissa = ARINC424Line.parseInteger(line.raw(columns.lowerBound...(columns.lowerBound + 1))),
              let exponent = ARINC424Line.parseInteger(line.raw(columns.upperBound...columns.upperBound))
        else { throw line.error("RNP", columns, "not an RNP value") }
        return Double(mantissa) / pow(10, Double(exponent))
    }

    /// True for the first leg of the missed approach (column 42 of the description code is `M`).
    public var isFirstMissedApproachLeg: Bool {
        descriptionCode.count == 4 && descriptionCode[descriptionCode.index(descriptionCode.startIndex, offsetBy: 2)] == "M"
    }

    /// True for a fly-over fix (column 41 of the description code is `Y` or `B`).
    public var isFlyOver: Bool {
        guard descriptionCode.count == 4 else { return false }
        let c = descriptionCode[descriptionCode.index(after: descriptionCode.startIndex)]
        return c == "Y" || c == "B"
    }
}
