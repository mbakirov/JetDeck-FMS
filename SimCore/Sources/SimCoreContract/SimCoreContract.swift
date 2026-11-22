// SimCoreContract.swift
//
// Contract between the simulation core (SimCore) and the iPad application.
// The application sends InputEvent values. The core returns Snapshot values.
// The application has no simulation logic. The core has no UI code.
//
// Status: v1. This file is compiled and tested in the SimCore package.

import Foundation

/// Fixed simulation step in seconds (50 Hz). This value is a proposal.
public let simStepSeconds: Double = 0.02

/// Increase this number when the event or snapshot format changes.
/// Recordings with a different version cannot be replayed.
public let contractSchemaVersion: Int = 1

// MARK: - Facade

/// The only entry point to the core.
///
/// Thread rules:
/// - `send` is safe to call from any thread. The event is applied at the start of the next step.
/// - `step` is called by one runner thread only.
/// - `latestSnapshot` is safe to read from any thread.
///
/// Pause and simulation rate are not core functions.
/// The runner stops or changes its calls to `step`.
public protocol SimCoreProtocol: AnyObject, Sendable {
    func send(_ event: InputEvent)
    @discardableResult func step() -> Snapshot
    var latestSnapshot: Snapshot { get }
}

/// One line of a flight recording. A recording is the scenario plus a list of these lines.
public struct RecordedEvent: Sendable, Codable, Equatable {
    public var step: UInt64
    public var event: InputEvent

    public init(
        step: UInt64,
        event: InputEvent
    ) {
        self.step = step
        self.event = event
    }
}

// MARK: - Settings

/// Application settings that the core gets when it is created.
/// A change of settings applies at the next start of a scenario.
public struct CoreSettings: Sendable, Codable, Equatable {
    /// Radio heights in feet that have an active callout. Example: [50, 40, 30, 20, 10].
    @CanonicalSet public var radioHeightCallouts: Set<Int>

    public init(
        radioHeightCallouts: Set<Int>
    ) {
        self.radioHeightCallouts = radioHeightCallouts
    }
}

// MARK: - Input events

/// An event is a physical action on a control. It is not an intention.
/// Example: "the ALT knob was pulled", not "engage OP CLB".
/// The core decides what the action means.
public enum InputEvent: Sendable, Codable, Equatable {
    case fcu(FCUEvent)
    case efis(EFISEvent)
    case mcdu(MCDUKey)
    case pedestal(PedestalEvent)
    case stick(StickEvent)
    case glareshield(GlareshieldEvent)
    case scenario(ScenarioEvent)
}

// MARK: FCU

public enum FCUKnob: String, Sendable, Codable, Hashable {
    case speed, heading, altitude, verticalSpeed
}

public enum FCUButton: String, Sendable, Codable, Hashable {
    case ap1, ap2, athr, loc, appr, exped
    case spdMach      // SPD / MACH changeover
    case hdgTrk       // HDG-V/S / TRK-FPA changeover
    case metricAlt
}

public enum AltitudeIncrement: Int, Sendable, Codable, Hashable {
    case hundred = 100
    case thousand = 1000
}

public enum FCUEvent: Sendable, Codable, Equatable {
    /// One click is one detent of the knob. Positive is clockwise.
    case knobTurned(FCUKnob, clicks: Int)
    case knobPushed(FCUKnob)
    case knobPulled(FCUKnob)
    case buttonPressed(FCUButton)
    case altitudeIncrementSet(AltitudeIncrement)
}

// MARK: EFIS control panel (captain side only in the MVP)

public enum BaroUnit: String, Sendable, Codable, Hashable {
    case hPa, inHg
}

public enum EFISButton: String, Sendable, Codable, Hashable {
    case fd, ls, cstr, wpt, vorD, ndb, arpt
}

public enum NDMode: String, Sendable, Codable, Hashable {
    case roseILS, roseVOR, roseNav, arc, plan
}

public enum NDRange: Int, Sendable, Codable, Hashable {
    case nm10 = 10, nm20 = 20, nm40 = 40, nm80 = 80, nm160 = 160, nm320 = 320
}

public enum NavaidSelector: String, Sendable, Codable, Hashable {
    case adf, off, vor
}

public enum EFISEvent: Sendable, Codable, Equatable {
    case baroKnobTurned(clicks: Int)
    case baroKnobPushed                 // selects STD
    case baroKnobPulled                 // selects QNH
    case baroUnitSet(BaroUnit)
    case buttonPressed(EFISButton)
    case ndModeSet(NDMode)
    case ndRangeSet(NDRange)
    /// index is 1 or 2.
    case navaidSelectorSet(index: Int, NavaidSelector)
}

// MARK: MCDU

public enum MCDUSide: String, Sendable, Codable, Hashable {
    case left, right
}

public enum MCDUPageKey: String, Sendable, Codable, Hashable {
    case dir, prog, perf, initialization, data
    case fPln, radNav, fuelPred, secFPln, atcComm, mcduMenu, airport
}

public enum MCDUKey: Sendable, Codable, Equatable {
    /// row is 1...6.
    case lineSelect(MCDUSide, row: Int)
    case page(MCDUPageKey)
    case slewUp, slewDown, slewLeft, slewRight
    /// ASCII code of A...Z or 0...9.
    case character(UInt8)
    case dot, slash, plusMinus, space, overfly
    case clear
    /// CLR key held. Erases the full scratchpad.
    case clearHeld
}

// MARK: Pedestal

public enum FlapLeverPosition: Int, Sendable, Codable, Hashable {
    case zero = 0, one, two, three, full
}

public enum GearLeverPosition: String, Sendable, Codable, Hashable {
    case up, down
}

public enum PedestalEvent: Sendable, Codable, Equatable {
    /// Both levers move together in the MVP.
    /// Detents: IDLE 0, CL 25, FLX/MCT 35, TOGA 45 degrees. Verify these values with the FCOM.
    /// The UI snaps the lever to a detent. The core accepts any angle.
    case thrustLeversMoved(angleDeg: Double)
    case athrDisconnectPressed
    case flapLeverMoved(FlapLeverPosition)
    case gearLeverMoved(GearLeverPosition)
    /// 0 is retracted, 1 is full.
    case speedBrakeLeverMoved(position: Double)
    case groundSpoilersArmed(Bool)
}

// MARK: Other controls

public enum StickEvent: Sendable, Codable, Equatable {
    /// Takeover pushbutton on the sidestick. Disconnects the autopilot.
    case apDisconnectPressed
}

public enum GlareshieldEvent: Sendable, Codable, Equatable {
    case masterWarningPressed
    case masterCautionPressed
}

/// Actions of the user on scenario items. They are not actions on aircraft controls.
/// A restart is not an event. To restart, the application creates a new core.
public enum ScenarioEvent: Sendable, Codable, Equatable {
    /// The user confirmed the ATC message with this sequence number.
    case messageAcknowledged(seq: UInt64)
}

// MARK: - Snapshot

/// The full output of the core after one step.
///
/// Rules:
/// - The snapshot contains data that is ready to show. It does not contain internal state.
/// - Units are the units on the display (kt, ft, ft/min, degrees, NM).
/// - A nil value means "do not show" or "show a failure flag".
/// - The UI can skip snapshots. Thus one-time items (sounds, messages) have a sequence number.
public struct Snapshot: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var step: UInt64
    public var simTimeSeconds: Double
    public var utcSecondsOfDay: Int

    public var pfd: PFDData
    public var nd: NDData
    public var ewd: EWDData
    public var mcdu: MCDUScreen
    public var fcu: FCUDisplay
    public var controls: ControlsState
    public var audio: AudioState
    public var scenario: ScenarioStatus

    public init(
        schemaVersion: Int,
        step: UInt64,
        simTimeSeconds: Double,
        utcSecondsOfDay: Int,
        pfd: PFDData,
        nd: NDData,
        ewd: EWDData,
        mcdu: MCDUScreen,
        fcu: FCUDisplay,
        controls: ControlsState,
        audio: AudioState,
        scenario: ScenarioStatus
    ) {
        self.schemaVersion = schemaVersion
        self.step = step
        self.simTimeSeconds = simTimeSeconds
        self.utcSecondsOfDay = utcSecondsOfDay
        self.pfd = pfd
        self.nd = nd
        self.ewd = ewd
        self.mcdu = mcdu
        self.fcu = fcu
        self.controls = controls
        self.audio = audio
        self.scenario = scenario
    }
}

public enum DisplayColor: String, Sendable, Codable, Hashable {
    case green, white, cyan, magenta, amber, red, yellow, grey
}

public struct TextLine: Sendable, Codable, Equatable {
    public var text: String
    public var color: DisplayColor

    public init(
        text: String,
        color: DisplayColor
    ) {
        self.text = text
        self.color = color
    }
}

public struct GeoPoint: Sendable, Codable, Equatable {
    public var latDeg: Double
    public var lonDeg: Double

    public init(
        latDeg: Double,
        lonDeg: Double
    ) {
        self.latDeg = latDeg
        self.lonDeg = lonDeg
    }
}

// MARK: PFD

/// One text item on the FMA. The FMA is a grid of 3 rows and 5 columns.
public struct FMACell: Sendable, Codable, Equatable {
    public var row: Int          // 0...2
    public var column: Int       // 0...4
    public var span: Int         // number of columns. Example: LAND uses columns 1 and 2.
    public var text: String
    public var color: DisplayColor
    public var boxed: Bool       // white box after a mode change

    public init(
        row: Int,
        column: Int,
        span: Int,
        text: String,
        color: DisplayColor,
        boxed: Bool
    ) {
        self.row = row
        self.column = column
        self.span = span
        self.text = text
        self.color = color
        self.boxed = boxed
    }
}

public struct SpeedTarget: Sendable, Codable, Equatable {
    public var kt: Double
    public var managed: Bool     // true = magenta, false = cyan

    public init(
        kt: Double,
        managed: Bool
    ) {
        self.kt = kt
        self.managed = managed
    }
}

public struct SpeedTape: Sendable, Codable, Equatable {
    public var casKt: Double?
    /// Speed in 10 seconds minus the present speed.
    public var trendKt: Double?
    public var mach: Double?
    public var target: SpeedTarget?
    // Characteristic speeds. nil = not shown.
    public var vls: Double?
    public var vAlphaProt: Double?
    public var vAlphaMax: Double?
    public var vMax: Double?
    public var vfeNext: Double?
    public var greenDot: Double?
    public var sSpeed: Double?
    public var fSpeed: Double?

    public init(
        casKt: Double? = nil,
        trendKt: Double? = nil,
        mach: Double? = nil,
        target: SpeedTarget? = nil,
        vls: Double? = nil,
        vAlphaProt: Double? = nil,
        vAlphaMax: Double? = nil,
        vMax: Double? = nil,
        vfeNext: Double? = nil,
        greenDot: Double? = nil,
        sSpeed: Double? = nil,
        fSpeed: Double? = nil
    ) {
        self.casKt = casKt
        self.trendKt = trendKt
        self.mach = mach
        self.target = target
        self.vls = vls
        self.vAlphaProt = vAlphaProt
        self.vAlphaMax = vAlphaMax
        self.vMax = vMax
        self.vfeNext = vfeNext
        self.greenDot = greenDot
        self.sSpeed = sSpeed
        self.fSpeed = fSpeed
    }
}

public enum BaroReference: Sendable, Codable, Equatable {
    case standard
    case qnhHPa(Int)
    case qnhInHg(Double)
}

public struct AltitudeTarget: Sendable, Codable, Equatable {
    public var ft: Int
    public var isConstraint: Bool    // true = magenta, false = cyan

    public init(
        ft: Int,
        isConstraint: Bool
    ) {
        self.ft = ft
        self.isConstraint = isConstraint
    }
}

public enum MinimumsKind: String, Sendable, Codable, Hashable {
    case baro, radio
}

public struct Minimums: Sendable, Codable, Equatable {
    public var kind: MinimumsKind
    public var ft: Int

    public init(
        kind: MinimumsKind,
        ft: Int
    ) {
        self.kind = kind
        self.ft = ft
    }
}

public enum AltitudeAlert: String, Sendable, Codable, Hashable {
    case none, pulsing, flashing
}

public struct AltitudeTape: Sendable, Codable, Equatable {
    public var baroAltFt: Double?
    public var target: AltitudeTarget?
    public var reference: BaroReference
    public var radioAltFt: Double?
    public var minimums: Minimums?
    public var verticalSpeedFpm: Double?
    public var alert: AltitudeAlert

    public init(
        baroAltFt: Double? = nil,
        target: AltitudeTarget? = nil,
        reference: BaroReference,
        radioAltFt: Double? = nil,
        minimums: Minimums? = nil,
        verticalSpeedFpm: Double? = nil,
        alert: AltitudeAlert
    ) {
        self.baroAltFt = baroAltFt
        self.target = target
        self.reference = reference
        self.radioAltFt = radioAltFt
        self.minimums = minimums
        self.verticalSpeedFpm = verticalSpeedFpm
        self.alert = alert
    }
}

public struct HeadingTape: Sendable, Codable, Equatable {
    public var headingMagDeg: Double?
    public var trackMagDeg: Double?
    public var selectedHeadingDeg: Double?
    public var ilsCourseDeg: Double?

    public init(
        headingMagDeg: Double? = nil,
        trackMagDeg: Double? = nil,
        selectedHeadingDeg: Double? = nil,
        ilsCourseDeg: Double? = nil
    ) {
        self.headingMagDeg = headingMagDeg
        self.trackMagDeg = trackMagDeg
        self.selectedHeadingDeg = selectedHeadingDeg
        self.ilsCourseDeg = ilsCourseDeg
    }
}

public struct ILSData: Sendable, Codable, Equatable {
    public var ident: String?
    public var frequencyMHz: Double
    public var courseDeg: Double?
    public var dmeNM: Double?
    public var locDeviationDots: Double?
    public var gsDeviationDots: Double?

    public init(
        ident: String? = nil,
        frequencyMHz: Double,
        courseDeg: Double? = nil,
        dmeNM: Double? = nil,
        locDeviationDots: Double? = nil,
        gsDeviationDots: Double? = nil
    ) {
        self.ident = ident
        self.frequencyMHz = frequencyMHz
        self.courseDeg = courseDeg
        self.dmeNM = dmeNM
        self.locDeviationDots = locDeviationDots
        self.gsDeviationDots = gsDeviationDots
    }
}

public enum FlightDirector: Sendable, Codable, Equatable {
    /// HDG-V/S reference. A nil value removes that bar.
    case bars(pitchDeg: Double?, rollDeg: Double?)
    /// TRK-FPA reference.
    case flightPathDirector(fpaDeg: Double, rollDeg: Double)
}

public struct FlightPathVector: Sendable, Codable, Equatable {
    public var fpaDeg: Double
    public var driftDeg: Double

    public init(
        fpaDeg: Double,
        driftDeg: Double
    ) {
        self.fpaDeg = fpaDeg
        self.driftDeg = driftDeg
    }
}

public struct PFDData: Sendable, Codable, Equatable {
    public var fma: [FMACell]
    public var pitchDeg: Double?
    public var rollDeg: Double?
    public var flightDirector: FlightDirector?
    public var flightPathVector: FlightPathVector?
    public var speed: SpeedTape
    public var altitude: AltitudeTape
    public var heading: HeadingTape
    /// nil when the LS pushbutton is off.
    public var ils: ILSData?
    public var flags: [TextLine]

    public init(
        fma: [FMACell],
        pitchDeg: Double? = nil,
        rollDeg: Double? = nil,
        flightDirector: FlightDirector? = nil,
        flightPathVector: FlightPathVector? = nil,
        speed: SpeedTape,
        altitude: AltitudeTape,
        heading: HeadingTape,
        ils: ILSData? = nil,
        flags: [TextLine]
    ) {
        self.fma = fma
        self.pitchDeg = pitchDeg
        self.rollDeg = rollDeg
        self.flightDirector = flightDirector
        self.flightPathVector = flightPathVector
        self.speed = speed
        self.altitude = altitude
        self.heading = heading
        self.ils = ils
        self.flags = flags
    }
}

// MARK: ND

public enum NDPathStyle: String, Sendable, Codable, Hashable {
    case active, temporary, missedApproach, secondary
}

public enum NDPathSegment: Sendable, Codable, Equatable {
    case line(from: GeoPoint, to: GeoPoint, style: NDPathStyle)
    case arc(center: GeoPoint, radiusNM: Double,
             startBearingDeg: Double, endBearingDeg: Double,
             clockwise: Bool, style: NDPathStyle)
}

public enum NDSymbolKind: String, Sendable, Codable, Hashable {
    case waypoint, activeWaypoint
    case vor, vorDme, dme, ndb, airport, runway
    // Pseudo waypoints
    case topOfClimb, topOfDescent, decel, levelOff, speedChange
}

public struct NDSymbol: Sendable, Codable, Equatable {
    public var kind: NDSymbolKind
    public var ident: String?
    public var position: GeoPoint
    /// Constraint text below the ident. Example: "+3000".
    public var annotation: String?
    /// Runway direction. Used only for the runway symbol.
    public var bearingDeg: Double?

    public init(
        kind: NDSymbolKind,
        ident: String? = nil,
        position: GeoPoint,
        annotation: String? = nil,
        bearingDeg: Double? = nil
    ) {
        self.kind = kind
        self.ident = ident
        self.position = position
        self.annotation = annotation
        self.bearingDeg = bearingDeg
    }
}

/// The geographic content of the ND. The UI projects it on the screen.
/// `version` changes only when the content changes. The UI can cache its drawing.
public struct NDMap: Sendable, Codable, Equatable {
    public var version: UInt64
    public var path: [NDPathSegment]
    public var symbols: [NDSymbol]

    public init(
        version: UInt64,
        path: [NDPathSegment],
        symbols: [NDSymbol]
    ) {
        self.version = version
        self.path = path
        self.symbols = symbols
    }
}

public struct WindData: Sendable, Codable, Equatable {
    public var directionDeg: Double
    public var speedKt: Double

    public init(
        directionDeg: Double,
        speedKt: Double
    ) {
        self.directionDeg = directionDeg
        self.speedKt = speedKt
    }
}

public struct ToWaypoint: Sendable, Codable, Equatable {
    public var ident: String
    public var bearingDeg: Double
    public var distanceNM: Double
    public var etaUTCSecondsOfDay: Int?

    public init(
        ident: String,
        bearingDeg: Double,
        distanceNM: Double,
        etaUTCSecondsOfDay: Int? = nil
    ) {
        self.ident = ident
        self.bearingDeg = bearingDeg
        self.distanceNM = distanceNM
        self.etaUTCSecondsOfDay = etaUTCSecondsOfDay
    }
}

public struct BearingPointer: Sendable, Codable, Equatable {
    public var index: Int                // 1 or 2
    public var kind: NavaidSelector
    public var ident: String?
    public var bearingDeg: Double?
    public var distanceNM: Double?

    public init(
        index: Int,
        kind: NavaidSelector,
        ident: String? = nil,
        bearingDeg: Double? = nil,
        distanceNM: Double? = nil
    ) {
        self.index = index
        self.kind = kind
        self.ident = ident
        self.bearingDeg = bearingDeg
        self.distanceNM = distanceNM
    }
}

public struct NDData: Sendable, Codable, Equatable {
    public var mode: NDMode
    public var range: NDRange
    public var position: GeoPoint?
    /// Map centre in PLAN mode.
    public var planCenter: GeoPoint?
    public var headingMagDeg: Double?
    public var trackMagDeg: Double?
    public var selectedHeadingDeg: Double?
    public var groundSpeedKt: Double?
    public var trueAirspeedKt: Double?
    public var wind: WindData?
    public var toWaypoint: ToWaypoint?
    /// Example: "ILS APP".
    public var approachMessage: String?
    public var crossTrackNM: Double?
    public var pointers: [BearingPointer]
    /// Used in ROSE ILS mode.
    public var ils: ILSData?
    public var map: NDMap
    public var flags: [TextLine]

    public init(
        mode: NDMode,
        range: NDRange,
        position: GeoPoint? = nil,
        planCenter: GeoPoint? = nil,
        headingMagDeg: Double? = nil,
        trackMagDeg: Double? = nil,
        selectedHeadingDeg: Double? = nil,
        groundSpeedKt: Double? = nil,
        trueAirspeedKt: Double? = nil,
        wind: WindData? = nil,
        toWaypoint: ToWaypoint? = nil,
        approachMessage: String? = nil,
        crossTrackNM: Double? = nil,
        pointers: [BearingPointer],
        ils: ILSData? = nil,
        map: NDMap,
        flags: [TextLine]
    ) {
        self.mode = mode
        self.range = range
        self.position = position
        self.planCenter = planCenter
        self.headingMagDeg = headingMagDeg
        self.trackMagDeg = trackMagDeg
        self.selectedHeadingDeg = selectedHeadingDeg
        self.groundSpeedKt = groundSpeedKt
        self.trueAirspeedKt = trueAirspeedKt
        self.wind = wind
        self.toWaypoint = toWaypoint
        self.approachMessage = approachMessage
        self.crossTrackNM = crossTrackNM
        self.pointers = pointers
        self.ils = ils
        self.map = map
        self.flags = flags
    }
}

// MARK: E/WD

public enum ThrustParameter: String, Sendable, Codable, Hashable {
    case epr, n1
}

public struct EngineData: Sendable, Codable, Equatable {
    /// EPR or N1 percent. See EWDData.thrustParameter.
    public var thrustActual: Double?
    public var thrustCommand: Double?
    public var egtC: Double?
    public var n1Percent: Double?
    public var n2Percent: Double?
    public var fuelFlowKgH: Double?

    public init(
        thrustActual: Double? = nil,
        thrustCommand: Double? = nil,
        egtC: Double? = nil,
        n1Percent: Double? = nil,
        n2Percent: Double? = nil,
        fuelFlowKgH: Double? = nil
    ) {
        self.thrustActual = thrustActual
        self.thrustCommand = thrustCommand
        self.egtC = egtC
        self.n1Percent = n1Percent
        self.n2Percent = n2Percent
        self.fuelFlowKgH = fuelFlowKgH
    }
}

public enum ThrustLimitMode: String, Sendable, Codable, Hashable {
    case toga, flx, mct, clb
}

public struct ThrustLimit: Sendable, Codable, Equatable {
    public var mode: ThrustLimitMode
    public var value: Double
    public var flexTempC: Int?

    public init(
        mode: ThrustLimitMode,
        value: Double,
        flexTempC: Int? = nil
    ) {
        self.mode = mode
        self.value = value
        self.flexTempC = flexTempC
    }
}

public struct SlatsFlaps: Sendable, Codable, Equatable {
    /// 0 is retracted, 1 is fully extended.
    public var slatPosition: Double
    public var flapPosition: Double
    /// "0", "1", "1+F", "2", "3" or "FULL".
    public var configLabel: String
    public var inTransit: Bool

    public init(
        slatPosition: Double,
        flapPosition: Double,
        configLabel: String,
        inTransit: Bool
    ) {
        self.slatPosition = slatPosition
        self.flapPosition = flapPosition
        self.configLabel = configLabel
        self.inTransit = inTransit
    }
}

public struct EWDData: Sendable, Codable, Equatable {
    public var thrustParameter: ThrustParameter
    public var engines: [EngineData]         // 2 items
    public var thrustLimit: ThrustLimit?
    /// Example: "IDLE", "A.FLOOR".
    public var athrMessage: TextLine?
    public var fuelOnBoardKg: Int?
    public var slatsFlaps: SlatsFlaps
    /// Warnings and memos on the left side.
    public var leftLines: [TextLine]
    public var rightLines: [TextLine]

    public init(
        thrustParameter: ThrustParameter,
        engines: [EngineData],
        thrustLimit: ThrustLimit? = nil,
        athrMessage: TextLine? = nil,
        fuelOnBoardKg: Int? = nil,
        slatsFlaps: SlatsFlaps,
        leftLines: [TextLine],
        rightLines: [TextLine]
    ) {
        self.thrustParameter = thrustParameter
        self.engines = engines
        self.thrustLimit = thrustLimit
        self.athrMessage = athrMessage
        self.fuelOnBoardKg = fuelOnBoardKg
        self.slatsFlaps = slatsFlaps
        self.leftLines = leftLines
        self.rightLines = rightLines
    }
}

// MARK: MCDU screen

public struct MCDUAttribute: Sendable, Codable, Equatable {
    public var color: DisplayColor
    public var small: Bool

    public init(
        color: DisplayColor,
        small: Bool
    ) {
        self.color = color
        self.small = small
    }
}

/// One row of the MCDU screen. `text` has exactly 24 characters.
/// `attributes` has 24 items, one for each character.
public struct MCDURow: Sendable, Codable, Equatable {
    public var text: String
    public var attributes: [MCDUAttribute]

    public init(
        text: String,
        attributes: [MCDUAttribute]
    ) {
        self.text = text
        self.attributes = attributes
    }
}

public enum MCDUAnnunciator: String, Sendable, Codable, Hashable {
    case fail, fm, mcduMenu, fm1, ind, rdy, fm2
}

/// 14 rows: title, 6 pairs of label and data rows, scratchpad.
public struct MCDUScreen: Sendable, Codable, Equatable {
    public var rows: [MCDURow]
    @CanonicalSet public var annunciators: Set<MCDUAnnunciator>

    public init(
        rows: [MCDURow],
        annunciators: Set<MCDUAnnunciator>
    ) {
        self.rows = rows
        self.annunciators = annunciators
    }
}

// MARK: FCU display

public struct FCUWindow: Sendable, Codable, Equatable {
    /// nil = dashes.
    public var text: String?
    public var managedDot: Bool

    public init(
        text: String? = nil,
        managedDot: Bool
    ) {
        self.text = text
        self.managedDot = managedDot
    }
}

public enum FCUSpeedUnit: String, Sendable, Codable, Hashable {
    case spd, mach
}

public enum FCUReference: String, Sendable, Codable, Hashable {
    case hdgVs, trkFpa
}

public struct FCUDisplay: Sendable, Codable, Equatable {
    public var speedUnit: FCUSpeedUnit
    public var speed: FCUWindow
    public var reference: FCUReference
    public var heading: FCUWindow
    public var altitudeFt: Int
    public var altitudeManagedDot: Bool
    public var verticalSpeed: FCUWindow
    public var altitudeIncrement: AltitudeIncrement
    /// Buttons with the light on.
    @CanonicalSet public var lights: Set<FCUButton>

    public init(
        speedUnit: FCUSpeedUnit,
        speed: FCUWindow,
        reference: FCUReference,
        heading: FCUWindow,
        altitudeFt: Int,
        altitudeManagedDot: Bool,
        verticalSpeed: FCUWindow,
        altitudeIncrement: AltitudeIncrement,
        lights: Set<FCUButton>
    ) {
        self.speedUnit = speedUnit
        self.speed = speed
        self.reference = reference
        self.heading = heading
        self.altitudeFt = altitudeFt
        self.altitudeManagedDot = altitudeManagedDot
        self.verticalSpeed = verticalSpeed
        self.altitudeIncrement = altitudeIncrement
        self.lights = lights
    }
}

// MARK: Control positions

public enum GearLight: String, Sendable, Codable, Hashable {
    case off, unlocked, downLocked
}

/// The positions of all controls and their lights.
/// The core is the source of truth. During a replay the UI moves the levers from this data.
public struct ControlsState: Sendable, Codable, Equatable {
    public var thrustLeverAngleDeg: Double
    public var flapLever: FlapLeverPosition
    public var gearLever: GearLeverPosition
    public var gearLights: [GearLight]       // nose, left, right
    public var speedBrakeLever: Double
    public var groundSpoilersArmed: Bool

    public var baroReference: BaroReference
    public var baroUnit: BaroUnit
    @CanonicalSet public var efisLights: Set<EFISButton>
    public var ndMode: NDMode
    public var ndRange: NDRange
    public var navaidSelectors: [NavaidSelector]   // 2 items

    public var masterWarningLit: Bool
    public var masterCautionLit: Bool

    public init(
        thrustLeverAngleDeg: Double,
        flapLever: FlapLeverPosition,
        gearLever: GearLeverPosition,
        gearLights: [GearLight],
        speedBrakeLever: Double,
        groundSpoilersArmed: Bool,
        baroReference: BaroReference,
        baroUnit: BaroUnit,
        efisLights: Set<EFISButton>,
        ndMode: NDMode,
        ndRange: NDRange,
        navaidSelectors: [NavaidSelector],
        masterWarningLit: Bool,
        masterCautionLit: Bool
    ) {
        self.thrustLeverAngleDeg = thrustLeverAngleDeg
        self.flapLever = flapLever
        self.gearLever = gearLever
        self.gearLights = gearLights
        self.speedBrakeLever = speedBrakeLever
        self.groundSpoilersArmed = groundSpoilersArmed
        self.baroReference = baroReference
        self.baroUnit = baroUnit
        self.efisLights = efisLights
        self.ndMode = ndMode
        self.ndRange = ndRange
        self.navaidSelectors = navaidSelectors
        self.masterWarningLit = masterWarningLit
        self.masterCautionLit = masterCautionLit
    }
}

// MARK: Audio

public enum Sound: String, Sendable, Codable, Hashable {
    case cavalryCharge                 // autopilot disconnection
    case tripleClick                   // mode reversion
    case cChord                        // altitude alert
    case singleChime                   // caution
    case continuousRepetitiveChime     // warning
    case calloutHundredAbove
    case calloutMinimum
    // Radio height callouts. The user selects the active set in the application settings.
    // See CoreSettings.radioHeightCallouts. Verify the list of possible heights with the FCOM.
    case callout2500, callout2000, callout1000, callout500, callout400, callout300, callout200
    case callout100, callout50, callout40, callout30, callout20, callout10, callout5
    /// Tells the pilot to move the thrust levers to IDLE.
    case calloutRetard
}

public struct AudioCue: Sendable, Codable, Equatable {
    public var seq: UInt64
    public var sound: Sound

    public init(
        seq: UInt64,
        sound: Sound
    ) {
        self.seq = seq
        self.sound = sound
    }
}

public struct AudioState: Sendable, Codable, Equatable {
    /// The last 8 one-time sounds. The UI plays each seq one time only.
    public var recentCues: [AudioCue]
    /// Sounds that play until the core removes them.
    @CanonicalSet public var continuous: Set<Sound>

    public init(
        recentCues: [AudioCue],
        continuous: Set<Sound>
    ) {
        self.recentCues = recentCues
        self.continuous = continuous
    }
}

// MARK: Scenario

public enum ScenarioPhase: String, Sendable, Codable, Hashable {
    case running, completed, failed
}

public struct ScenarioMessage: Sendable, Codable, Equatable {
    public var seq: UInt64
    public var simTimeSeconds: Double
    /// Example: "Turn left heading 250, descend 3000 ft".
    public var text: String

    public init(
        seq: UInt64,
        simTimeSeconds: Double,
        text: String
    ) {
        self.seq = seq
        self.simTimeSeconds = simTimeSeconds
        self.text = text
    }
}

/// The state of the aircraft at touchdown. The scenario ends at touchdown.
/// `passed` is true only when all four checks are true.
public struct TouchdownResult: Sendable, Codable, Equatable {
    public var thrustLeversAtIdle: Bool
    public var gearDownAndLocked: Bool
    public var landingConfiguration: Bool
    public var verticalSpeedInTolerance: Bool
    public var verticalSpeedFpm: Double
    public var passed: Bool

    public init(
        thrustLeversAtIdle: Bool,
        gearDownAndLocked: Bool,
        landingConfiguration: Bool,
        verticalSpeedInTolerance: Bool,
        verticalSpeedFpm: Double,
        passed: Bool
    ) {
        self.thrustLeversAtIdle = thrustLeversAtIdle
        self.gearDownAndLocked = gearDownAndLocked
        self.landingConfiguration = landingConfiguration
        self.verticalSpeedInTolerance = verticalSpeedInTolerance
        self.verticalSpeedFpm = verticalSpeedFpm
        self.passed = passed
    }
}

public struct ScenarioStatus: Sendable, Codable, Equatable {
    public var phase: ScenarioPhase
    public var recentMessages: [ScenarioMessage]
    /// nil before touchdown.
    public var touchdown: TouchdownResult?

    public init(
        phase: ScenarioPhase,
        recentMessages: [ScenarioMessage],
        touchdown: TouchdownResult? = nil
    ) {
        self.phase = phase
        self.recentMessages = recentMessages
        self.touchdown = touchdown
    }
}
