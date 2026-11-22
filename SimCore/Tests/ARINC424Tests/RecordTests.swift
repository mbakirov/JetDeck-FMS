import Foundation
import Testing
@testable import ARINC424

// Lines from FAACIFP18, cycle 2611.
enum Lines {
    static let airportJFK = "SUSAP KJFKK6AJFK     0     145YHN40382374W073464329W013000013         1800018000C    MNAR    JOHN F KENNEDY INTL           303911912"
    static let runway04L = "SUSAP KJFKK6GRW04L   0120790440 N40372318W073470505         -0028300012046057200IIHIQ1                                     308521709"
    static let runwayNoBearing = "SUSAP 13FDK7GNW      017302     N27573597W081301408               00060000050300D                                          828172108"
    static let waterRunway = "SCANP 5KE PAGE       0038930938 N55204915W131401567               00000000050999D                                          050851703"
    static let ilsIHIQ = "SUSAP KJFKK6IIHIQ1   011090RW04LN40390697W0734543940438N40373109W0734654890605 10890328300W01305700010                     308602308"
    static let vorJFK = "SUSAD        JFK   K6011590VDHW N40375838W073461701    N40375840W073461700W0120000102     NARKENNEDY                       254132609"
    static let dmeAAT = "SUSAD        AAT   K2011665 DHW                    AAT N41290007W120334155E0133043782     NARALTURAS                       248982605"
    static let ndbDDP = "SLAMDB       DDP   TJ003910H HW N18280580W066244461                       W0110           NARDORADO                        184251605"
    static let terminalNDB = "SLAMPNTJSJTJ SJ    TJ003300HO W N18243207W066052241                       W0110           NARPATTY                         194462108"
    static let enrouteWaypoint = "SUSAEAENRT   AGARD K60    C   L N39023689W076041114                       W0112     NAR           AGARD                    273562504"
    static let terminalWaypoint = "SUSAP KJFKK6CAROKE K60    R     N40282056W073540760                       W0125     NAR           AROKE                    303922504"
    static let airway = "SUSAER       T461        0110BELTTK6EA0E    RL                        326200320546 01800     06000                         629302512"
    static let legCF = "SUSAP KJFKK6FI04L  I      020KRSTLK6PC0E  F    CF IHIQK6      2238006504400060PI  H 0150001500            JFK   K6D 0 NS   305792006"
    static let legRunway = "SUSAP KJFKK6FI04L  I      030RW04LK6PG0GY M    CF IHIQK6      2238002004400045PI    00069             -300          0 NS   305802308"
    static let legHold = "SUSAP KJFKK6FI04L  I      060DUFFYK6PC0EE  L   HM                     2420T010    + 03000                           0 NS   305831310"
    static let legRF = "SCANP PADLPAFH01-Y ABROUS 030FISAXPAPC0EE BL010RF       0036101332    01530075    + 02800                 CFNPX PAPCA FS   068802409"
    static let legContinuation = "SCANP PANCPAFH07RZ H      020TULLIPAPC2W                                                A031                          FS   105351501"
    static let airspace = "SCANUCPAAPANC PAC  A00100     H N61103600W149585900                              GND  A04100MANCHORAGE                     145522205"

    static func line(_ text: String, number: Int = 1) -> ARINC424Line {
        ARINC424Line(number: number, text)!
    }
}

@Test func allTestLinesHave132Columns() {
    for text in [Lines.airportJFK, Lines.runway04L, Lines.runwayNoBearing, Lines.waterRunway, Lines.ilsIHIQ, Lines.vorJFK,
                 Lines.dmeAAT, Lines.ndbDDP, Lines.terminalNDB, Lines.enrouteWaypoint, Lines.terminalWaypoint, Lines.airway,
                 Lines.legCF, Lines.legRunway, Lines.legHold, Lines.legRF, Lines.legContinuation, Lines.airspace] {
        #expect(text.utf8.count == 132, "\(text.prefix(20))")
    }
}

@Test func lineLengthIsChecked() {
    #expect(ARINC424Line(number: 1, "TOO SHORT") == nil)
    #expect(ARINC424Line(number: 1, bytes: Array((Lines.airportJFK + "\r").utf8)) != nil)
    #expect(ARINC424Line(number: 1, Lines.airportJFK + " ") == nil)
}

@Test func lineClassUsesSectionAndSubsection() {
    #expect(Lines.line(Lines.airportJFK).lineClass == .primary(.airport))
    #expect(Lines.line(Lines.terminalNDB).lineClass == .primary(.terminalNDB))
    #expect(Lines.line(Lines.vorJFK).lineClass == .primary(.vhfNavaid))
    #expect(Lines.line(Lines.ndbDDP).lineClass == .primary(.enrouteNDB))
    #expect(Lines.line(Lines.airway).lineClass == .primary(.airway))
    #expect(Lines.line(Lines.legRF).lineClass == .primary(.approach))
    #expect(Lines.line(Lines.legContinuation).lineClass == .continuation(.approach))
    #expect(Lines.line(Lines.airspace).lineClass == .other(code: "UC"))
}

@Test func airportRecord() throws {
    let r = try AirportRecord(Lines.line(Lines.airportJFK))
    #expect(r.area == "USA")
    #expect(r.ident == "KJFK")
    #expect(r.region == "K6")
    #expect(r.iata == "JFK")
    #expect(r.longestRunwayFt == 14500)
    #expect(r.ifrCapable)
    #expect(r.longestRunwaySurface == "H")
    #expect(abs(r.position.latitude - (40 + 38.0 / 60 + 23.74 / 3600)) < 1e-12)
    #expect(abs(r.position.longitude + (73 + 46.0 / 60 + 43.29 / 3600)) < 1e-12)
    #expect(r.magneticVariation == -13.0)
    #expect(r.elevationFt == 13)
    #expect(r.transitionAltitudeFt == 18000)
    #expect(r.transitionLevelFt == 18000)
    #expect(r.publicMilitary == "C")
    #expect(r.datum == "NAR")
    #expect(r.name == "JOHN F KENNEDY INTL")
}

@Test func runwayRecord() throws {
    let r = try RunwayRecord(Lines.line(Lines.runway04L))
    #expect(r.airport == "KJFK")
    #expect(r.ident == "RW04L")
    #expect(r.lengthFt == 12079)
    #expect(r.bearing == ARINC424Bearing(degrees: 44.0, isTrue: false))
    #expect(abs(r.threshold.latitude - (40 + 37.0 / 60 + 23.18 / 3600)) < 1e-12)
    #expect(r.thresholdElevationFt == 12)
    #expect(r.displacedThresholdFt == 460)
    #expect(r.thresholdCrossingHeightFt == 57)
    #expect(r.widthFt == 200)
    #expect(r.localizer == "IHIQ")
    #expect(r.localizerCategory == "1")
}

@Test func runwayWithoutBearingAndWaterRunway() throws {
    let noBearing = try RunwayRecord(Lines.line(Lines.runwayNoBearing))
    #expect(noBearing.bearing == nil)
    #expect(noBearing.ident == "NW")
    // The value in the file (columns 23-27 are "17302").
    #expect(noBearing.lengthFt == 17302)
    let water = try RunwayRecord(Lines.line(Lines.waterRunway))
    #expect(water.ident == "E")
    #expect(water.bearing?.degrees == 93.8)
}

@Test func localizerRecord() throws {
    let r = try LocalizerRecord(Lines.line(Lines.ilsIHIQ))
    #expect(r.ident == "IHIQ")
    #expect(r.category == "1")
    #expect(r.isILSWithGlideSlope)
    #expect(r.frequencyMHz == 110.90)
    #expect(r.runway == "RW04L")
    #expect(r.localizerBearing == ARINC424Bearing(degrees: 43.8, isTrue: false))
    #expect(r.glideSlopePosition != nil)
    #expect(r.localizerPositionFt == 605)
    #expect(r.glideSlopePositionFt == 1089)
    #expect(r.localizerWidthDeg == 3.28)
    #expect(r.glideSlopeAngleDeg == 3.00)
    #expect(r.stationDeclination == -13.0)
    #expect(r.glideSlopeHeightAtThresholdFt == 57)
    #expect(r.glideSlopeElevationFt == 10)
}

@Test func vhfNavaidRecords() throws {
    let vor = try VHFNavaidRecord(Lines.line(Lines.vorJFK))
    #expect(vor.airport == nil)
    #expect(vor.ident == "JFK")
    #expect(vor.region == "K6")
    #expect(vor.frequencyMHz == 115.90)
    #expect(vor.navaidClass == "VDHW ")
    #expect(vor.vorPosition != nil)
    #expect(vor.dmePosition != nil)
    #expect(vor.stationDeclination == -12.0)
    #expect(vor.dmeElevationFt == 10)
    #expect(vor.name == "KENNEDY")

    let dme = try VHFNavaidRecord(Lines.line(Lines.dmeAAT))
    #expect(dme.vorPosition == nil)
    #expect(dme.position == dme.dmePosition)
    #expect(dme.navaidClass == " DHW ")
    #expect(dme.stationDeclination == 13.3)
}

@Test func ndbRecords() throws {
    let enroute = try NDBRecord(Lines.line(Lines.ndbDDP))
    #expect(enroute.airport == nil)
    #expect(enroute.ident == "DDP")
    #expect(enroute.frequencyKHz == 391.0)
    #expect(enroute.name == "DORADO")
    let terminal = try NDBRecord(Lines.line(Lines.terminalNDB))
    #expect(terminal.airport == "TJSJ")
    #expect(terminal.ident == "SJ")
    #expect(terminal.frequencyKHz == 330.0)
    #expect(terminal.navaidClass.hasPrefix("HO"))
}

@Test func waypointRecords() throws {
    let enroute = try WaypointRecord(Lines.line(Lines.enrouteWaypoint))
    #expect(enroute.airport == nil)
    #expect(enroute.ident == "AGARD")
    #expect(enroute.region == "K6")
    #expect(enroute.type == "C  ")
    #expect(enroute.usage == " L")
    #expect(enroute.magneticVariation == -11.2)
    let terminal = try WaypointRecord(Lines.line(Lines.terminalWaypoint))
    #expect(terminal.airport == "KJFK")
    #expect(terminal.ident == "AROKE")
    #expect(terminal.name == "AROKE")
}

@Test func airwayRecord() throws {
    let r = try AirwayFixRecord(Lines.line(Lines.airway))
    #expect(r.route == "T461")
    #expect(r.sequence == 110)
    #expect(r.fix == FixReference(ident: "BELTT", region: "K6", code: "EA"))
    #expect(r.routeType == "R")
    #expect(r.level == "L")
    #expect(r.outboundCourse == ARINC424Bearing(degrees: 326.2, isTrue: false))
    #expect(r.distanceNM == 3.2)
    #expect(r.inboundCourse == ARINC424Bearing(degrees: 54.6, isTrue: false))
    #expect(r.minimumAltitudeFt == 1800)
    #expect(r.maximumAltitudeFt == 6000)
}

@Test func procedureLegCF() throws {
    let r = try ProcedureLegRecord(Lines.line(Lines.legCF))
    #expect(r.kind == .approach)
    #expect(r.airport == "KJFK")
    #expect(r.procedure == "I04L")
    #expect(r.routeType == "I")
    #expect(r.transition == "")
    #expect(r.sequence == 20)
    #expect(r.fix == FixReference(ident: "KRSTL", region: "K6", code: "PC"))
    #expect(r.descriptionCode == "E  F")
    #expect(r.pathTerminator == "CF")
    #expect(r.recommendedNavaid == FixReference(ident: "IHIQ", region: "K6", code: "PI"))
    #expect(r.thetaDeg == 223.8)
    #expect(r.rhoNM == 6.5)
    #expect(r.course == ARINC424Bearing(degrees: 44.0, isTrue: false))
    #expect(r.distanceOrTime == .nauticalMiles(6.0))
    #expect(r.altitudeDescription == "H")
    #expect(r.altitude1Ft == 1500)
    #expect(r.altitude2Ft == 1500)
    #expect(r.centerFix == FixReference(ident: "JFK", region: "K6", code: "D"))
    #expect(r.routeQualifier1 == "N")
    #expect(r.routeQualifier2 == "S")
    #expect(!r.isFlyOver)
    #expect(!r.isFirstMissedApproachLeg)
}

@Test func procedureLegToRunwayAndHold() throws {
    let runway = try ProcedureLegRecord(Lines.line(Lines.legRunway))
    #expect(runway.fix?.code == "PG")
    #expect(runway.verticalAngleDeg == -3.00)
    #expect(runway.altitude1Ft == 69)
    #expect(runway.altitudeDescription == nil)
    #expect(runway.isFlyOver)

    let hold = try ProcedureLegRecord(Lines.line(Lines.legHold))
    #expect(hold.pathTerminator == "HM")
    #expect(hold.turnDirection == "L")
    #expect(hold.course?.degrees == 242.0)
    #expect(hold.distanceOrTime == .minutes(1.0))
    #expect(hold.altitudeDescription == "+")
    #expect(hold.altitude1Ft == 3000)
}

@Test func procedureLegRF() throws {
    let r = try ProcedureLegRecord(Lines.line(Lines.legRF))
    #expect(r.pathTerminator == "RF")
    #expect(r.transition == "BROUS")
    #expect(r.routeType == "A")
    #expect(r.turnDirection == "L")
    #expect(r.rnpNM == 1.0)
    #expect(r.arcRadiusNM == 3.61)
    #expect(r.course?.degrees == 15.3)
    #expect(r.distanceOrTime == .nauticalMiles(7.5))
    #expect(r.centerFix == FixReference(ident: "CFNPX", region: "PA", code: "PC"))
}

@Test func fieldErrorsNameTheColumns() {
    // The latitude has a letter in the degrees.
    var bytes = Array(Lines.airportJFK.utf8)
    bytes[33] = UInt8(ascii: "X")
    let line = ARINC424Line(number: 7, bytes: bytes)!
    #expect(throws: ARINC424Error.self) { try AirportRecord(line) }
    do {
        _ = try AirportRecord(line)
    } catch {
        #expect(error.line == 7)
        #expect(error.columns == 33...41)
        #expect(error.field == "airport reference point latitude")
    }
}

@Test func specialFieldFormats() throws {
    // Columns 71-75 of a copy of the airport line: test values are written there.
    func line(_ value: String) -> ARINC424Line {
        var bytes = Array(Lines.airportJFK.utf8)
        bytes.replaceSubrange(70..<75, with: Array(value.utf8))
        return ARINC424Line(number: 1, bytes: bytes)!
    }
    #expect(try line("FL180").altitude("a", 71...75) == 18000)
    #expect(try line("-0028").altitude("a", 71...75) == -28)
    #expect(try line("     ").altitude("a", 71...75) == nil)
    #expect(try line(" 044T").bearing("b", 72...75) == ARINC424Bearing(degrees: 44, isTrue: true))
    #expect(try line("T0130").magneticVariation("m", 71...75) == 0)
    #expect(try line("E0011").magneticVariation("m", 71...75) == 1.1)
    #expect(try line(" T010").distanceOrTime("d", 72...75) == .minutes(1.0))
    #expect(throws: ARINC424Error.self) { try line("12A45").integer("i", 71...75) }
    #expect(throws: ARINC424Error.self) { try line("X0130").magneticVariation("m", 71...75) }
}
