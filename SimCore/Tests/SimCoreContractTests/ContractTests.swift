import Foundation
import SimCoreContract
import Testing

let testInitial = InitialConditions(
    scenarioID: "test",
    settings: CoreSettings(radioHeightCallouts: [50, 10, 30, 100]),
    utcStartSecondsOfDay: 43_200,
    seed: 7
)

func requireContractType<T: Sendable & Codable & Equatable>(_: T.Type) {}

func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try SimCoreJSON.decode(T.self, from: SimCoreJSON.encode(value))
}

/// A snapshot with data in the optional fields and in the sets.
func richSnapshot() -> Snapshot {
    var snapshot = Snapshot.initial(testInitial)
    snapshot.step = 1234
    snapshot.simTimeSeconds = 24.68
    snapshot.pfd.fma = [FMACell(row: 0, column: 1, span: 2, text: "LAND", color: .green, boxed: true)]
    snapshot.pfd.pitchDeg = 2.5
    snapshot.pfd.flightDirector = .bars(pitchDeg: 1.5, rollDeg: nil)
    snapshot.pfd.speed.casKt = 137.3
    snapshot.pfd.speed.target = SpeedTarget(kt: 137, managed: true)
    snapshot.pfd.altitude.reference = .qnhInHg(29.92)
    snapshot.pfd.altitude.minimums = Minimums(kind: .baro, ft: 480)
    snapshot.pfd.ils = ILSData(ident: "IJFK", frequencyMHz: 110.9, courseDeg: 44, locDeviationDots: -0.3)
    snapshot.nd.map = NDMap(
        version: 3,
        path: [
            .line(from: GeoPoint(latDeg: 40.6, lonDeg: -73.8), to: GeoPoint(latDeg: 40.7, lonDeg: -73.7), style: .active),
            .arc(center: GeoPoint(latDeg: 40.6, lonDeg: -73.8), radiusNM: 2, startBearingDeg: 10,
                 endBearingDeg: 90, clockwise: true, style: .missedApproach),
        ],
        symbols: [NDSymbol(kind: .runway, ident: "04R", position: GeoPoint(latDeg: 40.6, lonDeg: -73.8), bearingDeg: 44)]
    )
    snapshot.nd.pointers = [BearingPointer(index: 1, kind: .vor, ident: "JFK", bearingDeg: 12)]
    snapshot.ewd.thrustLimit = ThrustLimit(mode: .clb, value: 87.4)
    snapshot.ewd.athrMessage = TextLine(text: "IDLE", color: .green)
    snapshot.mcdu.annunciators = [.fm1, .rdy, .ind]
    snapshot.fcu.lights = [.loc, .ap1, .athr, .appr]
    snapshot.controls.efisLights = [.wpt, .ls, .fd]
    snapshot.audio.recentCues = [AudioCue(seq: 4, sound: .calloutRetard)]
    snapshot.audio.continuous = [.continuousRepetitiveChime, .cChord]
    snapshot.scenario.recentMessages = [ScenarioMessage(seq: 1, simTimeSeconds: 3, text: "Turn left heading 250")]
    snapshot.scenario.touchdown = TouchdownResult(
        thrustLeversAtIdle: true, gearDownAndLocked: true, landingConfiguration: true,
        verticalSpeedInTolerance: true, verticalSpeedFpm: -180, passed: true
    )
    return snapshot
}

@Test func contractTypesAreSendableCodableEquatable() {
    requireContractType(Snapshot.self)
    requireContractType(InputEvent.self)
    requireContractType(RecordedEvent.self)
    requireContractType(CoreSettings.self)
    requireContractType(InitialConditions.self)
    requireContractType(FlightRecording.self)
}

@Test func initialSnapshotHasValidShape() {
    let snapshot = Snapshot.initial(testInitial)
    #expect(snapshot.schemaVersion == contractSchemaVersion)
    #expect(snapshot.step == 0)
    #expect(snapshot.simTimeSeconds == 0)
    #expect(snapshot.utcSecondsOfDay == 43_200)
    #expect(snapshot.ewd.thrustParameter == .n1)
    #expect(snapshot.ewd.engines.count == 2)
    #expect(snapshot.mcdu.rows.count == 14)
    #expect(snapshot.mcdu.rows.allSatisfy { $0.text.count == 24 && $0.attributes.count == 24 })
    #expect(snapshot.controls.gearLights.count == 3)
    #expect(snapshot.controls.navaidSelectors.count == 2)
    #expect(snapshot.scenario.phase == .running)
}

@Test func snapshotRoundTripsThroughJSON() throws {
    #expect(try roundTrip(Snapshot.initial(testInitial)) == Snapshot.initial(testInitial))
    #expect(try roundTrip(richSnapshot()) == richSnapshot())
}

@Test func everyInputEventRoundTripsThroughJSON() throws {
    for event in InputEvent.samples {
        #expect(try roundTrip(event) == event)
    }
}

@Test func samplesCoverAllEventGroups() {
    var groups: Set<String> = []
    for event in InputEvent.samples {
        switch event {
        case .fcu: groups.insert("fcu")
        case .efis: groups.insert("efis")
        case .mcdu: groups.insert("mcdu")
        case .pedestal: groups.insert("pedestal")
        case .stick: groups.insert("stick")
        case .glareshield: groups.insert("glareshield")
        case .scenario: groups.insert("scenario")
        }
    }
    #expect(groups.count == 7)
}

@Test func setsHaveStableJSON() throws {
    let buttons: [FCUButton] = [.ap1, .ap2, .athr, .loc, .appr, .exped, .spdMach, .hdgTrk, .metricAlt]
    var first = richSnapshot()
    var second = richSnapshot()
    first.fcu.lights = []
    second.fcu.lights = []
    for button in buttons { first.fcu.lights.insert(button) }
    for button in buttons.reversed() { second.fcu.lights.insert(button) }
    first.audio.continuous = [.cChord, .singleChime, .tripleClick]
    second.audio.continuous = [.tripleClick, .singleChime, .cChord]
    #expect(first == second)
    #expect(try SimCoreJSON.encode(first) == SimCoreJSON.encode(second))

    let json = String(decoding: try SimCoreJSON.encode(CoreSettings(radioHeightCallouts: [50, 10, 30, 100])), as: UTF8.self)
    #expect(json == #"{"radioHeightCallouts":[10,30,50,100]}"#)
}

@Test func recordingRoundTrips() throws {
    let events = InputEvent.samples.enumerated().map { RecordedEvent(step: UInt64($0.offset / 3 + 1), event: $0.element) }
    let recording = FlightRecording(initial: testInitial, stepCount: 100, events: events)
    #expect(recording.schemaVersion == contractSchemaVersion)
    #expect(try FlightRecording.load(from: recording.encoded()) == recording)
}

@Test func recordingWithOtherContractVersionIsRejected() throws {
    var recording = FlightRecording(initial: testInitial, stepCount: 10, events: [])
    recording.schemaVersion = 999
    let data = try recording.encoded()
    #expect(throws: RecordingError.schemaVersionMismatch(found: 999, expected: contractSchemaVersion)) {
        try FlightRecording.load(from: data)
    }
    let message = RecordingError.schemaVersionMismatch(found: 999, expected: contractSchemaVersion).localizedDescription
    #expect(message.contains("999"))
    #expect(message.contains("version \(contractSchemaVersion)"))
}

@Test func versionIsCheckedBeforeTheOtherData() {
    // A future format can have other fields. The error must tell the version, not the missing field.
    let data = Data(#"{"schemaVersion":2,"newFormat":true}"#.utf8)
    #expect(throws: RecordingError.schemaVersionMismatch(found: 2, expected: contractSchemaVersion)) {
        try FlightRecording.load(from: data)
    }
}

@Test func malformedRecordingIsRejected() {
    for text in ["not json", "{}", #"{"schemaVersion":\#(contractSchemaVersion)}"#] {
        do {
            _ = try FlightRecording.load(from: Data(text.utf8))
            Issue.record("no error for: \(text)")
        } catch {
            guard case .malformed = error else {
                Issue.record("wrong error for: \(text): \(error)")
                continue
            }
        }
    }
}

@Test func recordingWithEventAfterLastStepIsRejected() throws {
    let recording = FlightRecording(
        initial: testInitial, stepCount: 5,
        events: [RecordedEvent(step: 6, event: .mcdu(.clear))]
    )
    let data = try recording.encoded()
    do {
        _ = try FlightRecording.load(from: data)
        Issue.record("no error")
    } catch {
        guard case .malformed = error else {
            Issue.record("wrong error: \(error)")
            return
        }
    }
}
