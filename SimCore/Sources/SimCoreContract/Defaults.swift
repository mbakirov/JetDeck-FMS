import Foundation

// Empty values of the snapshot sections.
// The core uses them before the simulation modules write real data.

extension SpeedTape {
    public static let blank = SpeedTape()
}

extension AltitudeTape {
    public static let blank = AltitudeTape(reference: .standard, alert: .none)
}

extension HeadingTape {
    public static let blank = HeadingTape()
}

extension PFDData {
    public static let blank = PFDData(
        fma: [], speed: .blank, altitude: .blank, heading: .blank, flags: []
    )
}

extension NDData {
    public static let blank = NDData(
        mode: .arc, range: .nm20, pointers: [],
        map: NDMap(version: 0, path: [], symbols: []), flags: []
    )
}

extension EWDData {
    public static let blank = EWDData(
        thrustParameter: .n1,
        engines: [EngineData(), EngineData()],
        slatsFlaps: SlatsFlaps(slatPosition: 0, flapPosition: 0, configLabel: "0", inTransit: false),
        leftLines: [], rightLines: []
    )
}

extension MCDURow {
    public static let columnCount = 24

    public static let blank = MCDURow(
        text: String(repeating: " ", count: columnCount),
        attributes: Array(repeating: MCDUAttribute(color: .white, small: false), count: columnCount)
    )
}

extension MCDUScreen {
    public static let rowCount = 14

    public static let blank = MCDUScreen(
        rows: Array(repeating: .blank, count: rowCount), annunciators: []
    )
}

extension FCUDisplay {
    public static let blank = FCUDisplay(
        speedUnit: .spd,
        speed: FCUWindow(managedDot: false),
        reference: .hdgVs,
        heading: FCUWindow(managedDot: false),
        altitudeFt: 0,
        altitudeManagedDot: false,
        verticalSpeed: FCUWindow(managedDot: false),
        altitudeIncrement: .hundred,
        lights: []
    )
}

extension ControlsState {
    public static let blank = ControlsState(
        thrustLeverAngleDeg: 0,
        flapLever: .zero,
        gearLever: .up,
        gearLights: [.off, .off, .off],
        speedBrakeLever: 0,
        groundSpoilersArmed: false,
        baroReference: .standard,
        baroUnit: .hPa,
        efisLights: [],
        ndMode: .arc,
        ndRange: .nm20,
        navaidSelectors: [.off, .off],
        masterWarningLit: false,
        masterCautionLit: false
    )
}

extension AudioState {
    public static let blank = AudioState(recentCues: [], continuous: [])
}

extension ScenarioStatus {
    public static let blank = ScenarioStatus(phase: .running, recentMessages: [])
}

extension Snapshot {
    /// The snapshot before the first step: step 0, time 0, empty displays.
    public static func initial(_ initial: InitialConditions) -> Snapshot {
        Snapshot(
            schemaVersion: contractSchemaVersion,
            step: 0,
            simTimeSeconds: 0,
            utcSecondsOfDay: initial.utcStartSecondsOfDay,
            pfd: .blank, nd: .blank, ewd: .blank, mcdu: .blank, fcu: .blank,
            controls: .blank, audio: .blank, scenario: .blank
        )
    }
}
