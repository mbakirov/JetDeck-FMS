import SimCoreContract

// Types of the navigation database. The FMS and Displays modules read the database through the protocol
// `NavDatabase`. The implementation on SQLite is in the target NavDB.

/// The kind of a point in the database.
public enum NavFixKind: String, Sendable, Codable, CaseIterable, Comparable {
    case airport
    case runway
    case localizer
    case vhfNavaid
    case ndb
    case waypoint

    public static func < (lhs: NavFixKind, rhs: NavFixKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The type of a radio navigation facility.
public enum NavaidType: String, Sendable, Codable, CaseIterable {
    case vor
    case vorDme
    case vortac
    case tacan
    case dme
    case ilsDme
    case ndb
    /// NDB collocated with a marker beacon (for example LOM).
    case locator
}

/// A course or bearing.
public struct NavCourse: Sendable, Equatable, Codable {
    public var degrees: Double
    /// True when the value is relative to true north. Otherwise it is magnetic.
    public var isTrue: Bool

    public init(degrees: Double, isTrue: Bool) {
        self.degrees = degrees
        self.isTrue = isTrue
    }
}

/// A point of any kind: airport, runway threshold, localizer, navaid, waypoint.
public struct NavFix: Sendable, Equatable, Identifiable {
    /// Row identifier in the database. It is stable for one database file only.
    public var id: Int64
    public var kind: NavFixKind
    public var ident: String
    /// ICAO region code, for example `K6`.
    public var region: String
    /// Airport of a terminal fix, runway or localizer. For an airport it is its own identifier.
    /// Nil for an en route fix.
    public var airport: String?
    public var position: GeoPoint
    /// Type of a navaid. Nil for other kinds.
    public var navaidType: NavaidType?

    public init(id: Int64, kind: NavFixKind, ident: String, region: String, airport: String?, position: GeoPoint, navaidType: NavaidType? = nil) {
        self.id = id
        self.kind = kind
        self.ident = ident
        self.region = region
        self.airport = airport
        self.position = position
        self.navaidType = navaidType
    }
}

/// A reference from a procedure leg or an airway to a fix.
/// `fix` is nil when the database has no such fix.
public struct NavFixRef: Sendable, Equatable {
    public var ident: String
    public var region: String
    /// ARINC 424 section and subsection of the referenced record, for example `PC`, `EA`, `D`.
    public var code: String
    public var fix: NavFix?

    public init(ident: String, region: String, code: String, fix: NavFix?) {
        self.ident = ident
        self.region = region
        self.code = code
        self.fix = fix
    }
}

public struct NavAirport: Sendable, Equatable {
    public var fix: NavFix
    public var iata: String?
    public var name: String
    public var elevationFt: Int
    /// East is positive.
    public var magneticVariationDeg: Double?
    public var transitionAltitudeFt: Int?
    public var transitionLevelFt: Int?
    public var longestRunwayFt: Int?
    public var speedLimitKt: Int?
    public var speedLimitAltitudeFt: Int?

    public init(fix: NavFix, iata: String?, name: String, elevationFt: Int, magneticVariationDeg: Double?,
                transitionAltitudeFt: Int?, transitionLevelFt: Int?, longestRunwayFt: Int?,
                speedLimitKt: Int?, speedLimitAltitudeFt: Int?) {
        self.fix = fix
        self.iata = iata
        self.name = name
        self.elevationFt = elevationFt
        self.magneticVariationDeg = magneticVariationDeg
        self.transitionAltitudeFt = transitionAltitudeFt
        self.transitionLevelFt = transitionLevelFt
        self.longestRunwayFt = longestRunwayFt
        self.speedLimitKt = speedLimitKt
        self.speedLimitAltitudeFt = speedLimitAltitudeFt
    }

    public var ident: String { fix.ident }
    public var position: GeoPoint { fix.position }
}

public struct NavRunway: Sendable, Equatable {
    /// The landing threshold. The identifier has the prefix, for example `RW04L`.
    public var fix: NavFix
    public var lengthFt: Int
    public var widthFt: Int?
    /// Nil for a few small airports that have no bearing in the source.
    public var bearing: NavCourse?
    public var thresholdElevationFt: Int?
    public var displacedThresholdFt: Int?
    public var thresholdCrossingHeightFt: Int?
    /// Identifier of the ILS for this runway.
    public var localizerIdent: String?
    public var localizerCategory: String?
    /// A second ILS, LOC or LDA for this runway, for example IVWH for KDCA RW19.
    public var secondLocalizerIdent: String?
    public var secondLocalizerCategory: String?

    public init(fix: NavFix, lengthFt: Int, widthFt: Int?, bearing: NavCourse?, thresholdElevationFt: Int?,
                displacedThresholdFt: Int?, thresholdCrossingHeightFt: Int?, localizerIdent: String?, localizerCategory: String?,
                secondLocalizerIdent: String? = nil, secondLocalizerCategory: String? = nil) {
        self.fix = fix
        self.lengthFt = lengthFt
        self.widthFt = widthFt
        self.bearing = bearing
        self.thresholdElevationFt = thresholdElevationFt
        self.displacedThresholdFt = displacedThresholdFt
        self.thresholdCrossingHeightFt = thresholdCrossingHeightFt
        self.localizerIdent = localizerIdent
        self.localizerCategory = localizerCategory
        self.secondLocalizerIdent = secondLocalizerIdent
        self.secondLocalizerCategory = secondLocalizerCategory
    }

    public var ident: String { fix.ident }
}

/// Localizer and glide slope of an ILS (also LOC only, LDA, SDF, IGS).
public struct NavILS: Sendable, Equatable {
    /// The localizer antenna.
    public var fix: NavFix
    /// ARINC 424 category: `0` localizer only, `1` `2` `3` ILS category, `I` IGS, `L` `A` LDA, `S` `F` SDF.
    public var category: String
    public var frequencyMHz: Double
    /// Runway with the prefix, for example `RW04L`.
    public var runway: String
    public var course: NavCourse
    public var glideSlopePosition: GeoPoint?
    public var glideSlopeAngleDeg: Double?
    public var localizerWidthDeg: Double?
    /// East is positive.
    public var declinationDeg: Double?
    public var glideSlopeElevationFt: Int?
    public var glideSlopeHeightAtThresholdFt: Int?

    public init(fix: NavFix, category: String, frequencyMHz: Double, runway: String, course: NavCourse,
                glideSlopePosition: GeoPoint?, glideSlopeAngleDeg: Double?, localizerWidthDeg: Double?,
                declinationDeg: Double?, glideSlopeElevationFt: Int?, glideSlopeHeightAtThresholdFt: Int?) {
        self.fix = fix
        self.category = category
        self.frequencyMHz = frequencyMHz
        self.runway = runway
        self.course = course
        self.glideSlopePosition = glideSlopePosition
        self.glideSlopeAngleDeg = glideSlopeAngleDeg
        self.localizerWidthDeg = localizerWidthDeg
        self.declinationDeg = declinationDeg
        self.glideSlopeElevationFt = glideSlopeElevationFt
        self.glideSlopeHeightAtThresholdFt = glideSlopeHeightAtThresholdFt
    }

    public var ident: String { fix.ident }
    /// True for an ILS with a glide slope (categories 1, 2 and 3).
    public var isILSWithGlideSlope: Bool { ["1", "2", "3"].contains(category) }
}

/// VOR, DME, VORTAC, TACAN, ILS/DME or NDB.
public struct NavNavaid: Sendable, Equatable {
    public var fix: NavFix
    public var type: NavaidType
    /// MHz for a VHF facility, kHz for an NDB.
    public var frequency: Double
    public var name: String
    /// Raw ARINC 424 class (5 characters).
    public var navaidClass: String
    /// Position of the DME when it is not at the VOR.
    public var dmePosition: GeoPoint?
    /// Station declination of a VHF facility or magnetic variation at an NDB. East is positive.
    public var declinationDeg: Double?
    public var elevationFt: Int?
    public var ilsDmeBiasNM: Double?

    public init(fix: NavFix, type: NavaidType, frequency: Double, name: String, navaidClass: String,
                dmePosition: GeoPoint?, declinationDeg: Double?, elevationFt: Int?, ilsDmeBiasNM: Double?) {
        self.fix = fix
        self.type = type
        self.frequency = frequency
        self.name = name
        self.navaidClass = navaidClass
        self.dmePosition = dmePosition
        self.declinationDeg = declinationDeg
        self.elevationFt = elevationFt
        self.ilsDmeBiasNM = ilsDmeBiasNM
    }

    public var ident: String { fix.ident }
}

public struct NavWaypoint: Sendable, Equatable {
    public var fix: NavFix
    /// Raw ARINC 424 waypoint type (3 characters).
    public var type: String
    /// Raw ARINC 424 waypoint usage (2 characters).
    public var usage: String
    public var name: String

    public init(fix: NavFix, type: String, usage: String, name: String) {
        self.fix = fix
        self.type = type
        self.usage = usage
        self.name = name
    }

    public var ident: String { fix.ident }
}

/// One fix of an en route airway.
public struct NavAirwayFix: Sendable, Equatable {
    /// ARINC 424 area code of the record, for example `USA` or `CAN`.
    public var area: String
    public var route: String
    /// Continuous part of the airway, 1-based. A new segment starts where the airway is broken: an end of the airway
    /// in the source, a part outside the US data, or another airway with the same name in another area.
    /// An airway that the source splits between two areas is one segment.
    public var segment: Int
    public var sequence: Int
    public var fix: NavFixRef
    public var descriptionCode: String
    public var routeType: String
    /// `B` all altitudes, `H` high, `L` low.
    public var level: String
    /// `F` forward only, `B` backward only, empty both directions.
    public var directionRestriction: String
    public var outboundCourse: NavCourse?
    public var inboundCourse: NavCourse?
    public var distanceNM: Double?
    public var minimumAltitudeFt: Int?
    /// The second minimum altitude (ARINC 424 columns 89-93), for the other direction of flight or for a different
    /// cruise table.
    public var minimumAltitude2Ft: Int?
    public var maximumAltitudeFt: Int?

    public init(area: String, route: String, segment: Int, sequence: Int, fix: NavFixRef, descriptionCode: String, routeType: String,
                level: String, directionRestriction: String, outboundCourse: NavCourse?, inboundCourse: NavCourse?, distanceNM: Double?,
                minimumAltitudeFt: Int?, minimumAltitude2Ft: Int?, maximumAltitudeFt: Int?) {
        self.area = area
        self.route = route
        self.segment = segment
        self.sequence = sequence
        self.fix = fix
        self.descriptionCode = descriptionCode
        self.routeType = routeType
        self.level = level
        self.directionRestriction = directionRestriction
        self.outboundCourse = outboundCourse
        self.inboundCourse = inboundCourse
        self.distanceNM = distanceNM
        self.minimumAltitudeFt = minimumAltitudeFt
        self.minimumAltitude2Ft = minimumAltitude2Ft
        self.maximumAltitudeFt = maximumAltitudeFt
    }
}

public enum NavProcedureKind: String, Sendable, Codable, CaseIterable {
    case sid = "SID"
    case star = "STAR"
    case approach = "APPROACH"
}

/// The role of one route of a procedure.
public enum NavTransitionRole: String, Sendable, Codable, CaseIterable {
    case runwayTransition
    case common
    case enrouteTransition
    case approachTransition
    /// Final approach and missed approach.
    case final
}

/// One route of a procedure: a transition, the common route or the final approach.
public struct NavProcedureTransition: Sendable, Equatable, Identifiable {
    public var id: Int64
    /// ARINC 424 route type, for example `I` (ILS final approach) or `A` (approach transition).
    public var routeType: String
    /// Transition identifier. Empty for a common route and for the final approach.
    public var ident: String
    public var role: NavTransitionRole

    public init(id: Int64, routeType: String, ident: String, role: NavTransitionRole) {
        self.id = id
        self.routeType = routeType
        self.ident = ident
        self.role = role
    }
}

public struct NavProcedure: Sendable, Equatable, Identifiable {
    public var id: Int64
    public var airport: String
    public var kind: NavProcedureKind
    /// Identifier, for example `I04L`, `CAMRN5`, `DEEZZ6`.
    public var ident: String
    /// Route type of the final approach, for example `I` ILS, `R` RNAV, `L` localizer. Nil for SID and STAR.
    public var approachType: String?
    /// Runway of an approach with the prefix, for example `RW04L`. Nil for a circling approach, SID and STAR.
    public var runway: String?
    /// Routes in the order of the database.
    public var transitions: [NavProcedureTransition]

    public init(id: Int64, airport: String, kind: NavProcedureKind, ident: String, approachType: String?, runway: String?, transitions: [NavProcedureTransition]) {
        self.id = id
        self.airport = airport
        self.kind = kind
        self.ident = ident
        self.approachType = approachType
        self.runway = runway
        self.transitions = transitions
    }
}

/// One leg of a procedure (ARINC 424 path and terminator).
public struct NavProcedureLeg: Sendable, Equatable {
    public var sequence: Int
    /// Path and terminator, for example `IF`, `TF`, `CF`, `RF`, `HM`.
    public var pathTerminator: String
    public var fix: NavFixRef?
    /// Raw ARINC 424 waypoint description code (4 characters).
    public var descriptionCode: String
    /// `L`, `R` or `E` (either).
    public var turnDirection: String?
    public var turnDirectionValid: Bool
    public var isFlyOver: Bool
    /// True for the first leg of the missed approach.
    public var isFirstMissedApproachLeg: Bool
    public var recommendedNavaid: NavFixRef?
    public var arcRadiusNM: Double?
    public var thetaDeg: Double?
    public var rhoNM: Double?
    public var course: NavCourse?
    public var distanceNM: Double?
    public var holdTimeMinutes: Double?
    /// ARINC 424 altitude description, for example `+` at or above, `-` at or below, `B` between.
    public var altitudeDescription: String?
    public var altitude1Ft: Int?
    public var altitude2Ft: Int?
    public var transitionAltitudeFt: Int?
    public var speedLimitKt: Int?
    /// `+` at or above, `-` at or below, empty or `@` at.
    public var speedLimitDescription: String?
    /// Negative for a descent.
    public var verticalAngleDeg: Double?
    /// The center fix field (ARINC 424 columns 107-116). For an RF leg it is the center of the arc. For other legs
    /// the FAA puts the center of the MSA there (a runway, an airport or a navaid), so use it as an arc center only
    /// when `pathTerminator` is `RF`. The center of an AF arc is `recommendedNavaid`.
    public var centerFix: NavFixRef?
    public var rnpNM: Double?

    public init(sequence: Int, pathTerminator: String, fix: NavFixRef?, descriptionCode: String, turnDirection: String?,
                turnDirectionValid: Bool, isFlyOver: Bool, isFirstMissedApproachLeg: Bool, recommendedNavaid: NavFixRef?,
                arcRadiusNM: Double?, thetaDeg: Double?, rhoNM: Double?, course: NavCourse?, distanceNM: Double?,
                holdTimeMinutes: Double?, altitudeDescription: String?, altitude1Ft: Int?, altitude2Ft: Int?,
                transitionAltitudeFt: Int?, speedLimitKt: Int?, speedLimitDescription: String?, verticalAngleDeg: Double?,
                centerFix: NavFixRef?, rnpNM: Double?) {
        self.sequence = sequence
        self.pathTerminator = pathTerminator
        self.fix = fix
        self.descriptionCode = descriptionCode
        self.turnDirection = turnDirection
        self.turnDirectionValid = turnDirectionValid
        self.isFlyOver = isFlyOver
        self.isFirstMissedApproachLeg = isFirstMissedApproachLeg
        self.recommendedNavaid = recommendedNavaid
        self.arcRadiusNM = arcRadiusNM
        self.thetaDeg = thetaDeg
        self.rhoNM = rhoNM
        self.course = course
        self.distanceNM = distanceNM
        self.holdTimeMinutes = holdTimeMinutes
        self.altitudeDescription = altitudeDescription
        self.altitude1Ft = altitude1Ft
        self.altitude2Ft = altitude2Ft
        self.transitionAltitudeFt = transitionAltitudeFt
        self.speedLimitKt = speedLimitKt
        self.speedLimitDescription = speedLimitDescription
        self.verticalAngleDeg = verticalAngleDeg
        self.centerFix = centerFix
        self.rnpNM = rnpNM
    }
}
