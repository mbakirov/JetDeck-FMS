import Foundation
import Kernel
import NavDB
import NavDBBuilder
import SimCoreContract
import Testing
import World

let sampleURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CIFP-sample-2611.txt")

/// The database of the CIFP test sample. It is made once for all tests of this file.
let sampleDatabase: NavDatabaseReader = {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("world-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("sample.sqlite").path
    _ = try! NavDBBuilder.build(cifp: Data(contentsOf: sampleURL), sourceFileName: "CIFP-sample-2611.txt", output: path)
    return try! NavDatabaseReader(path: path)
}()

/// Approach to Burlington (KBTV, elevation 335 ft in the CIFP sample): QNH 1030 hPa, ISA +20, wind layers.
let burlington = InitialConditions(
    scenarioID: "world-test",
    settings: CoreSettings(radioHeightCallouts: []),
    utcStartDate: UTCDate(year: 2026, month: 11, day: 26),
    utcStartSecondsOfDay: 86_000,
    seed: 3,
    aircraft: InitialAircraft(position: GeoPoint(latDeg: 44.2, lonDeg: -73.4), altitudeFt: 12_000),
    destinationAirport: "KBTV",
    weather: WeatherConditions(qnhHPa: 1030, isaDeviationC: 20, windLayers: [
        WindLayer(altitudeFt: 8000, directionDeg: 200, speedKt: 15),
        WindLayer(altitudeFt: 16_000, directionDeg: 260, speedKt: 45),
    ])
)

func run(_ module: inout WorldModule, _ state: inout SimState, steps: ClosedRange<UInt64>, initial: InitialConditions = burlington) {
    for step in steps {
        module.run(on: &state, context: StepContext(step: step, events: [], initial: initial))
    }
}

@Test func writesOnlyItsSection() {
    #expect(WorldModule.sectionKeyPath == \SimState.world)
    var state = SimState(initial: burlington)
    var module = WorldModule(navData: sampleDatabase)
    run(&module, &state, steps: 1...3)
    var expected = SimState(initial: burlington)
    expected.world = state.world
    #expect(state == expected)
}

/// Acceptance criterion: the terrain elevation is the elevation of the destination airport in the database.
@Test func terrainIsTheElevationOfTheDestinationInTheDatabase() throws {
    let airport = try #require(try sampleDatabase.airport("KBTV"))
    #expect(airport.elevationFt == 335)
    var state = SimState(initial: burlington)
    var module = WorldModule(navData: sampleDatabase)
    run(&module, &state, steps: 1...1)
    #expect(state.world.terrainElevationM == 335 * Units.metresPerFoot)
    #expect(state.world.environment?.destination == .found(airport))
    #expect(state.world.environment?.atmosphere.fieldElevationM == 335 * Units.metresPerFoot)
}

@Test func airportThatIsNotInTheDatabaseGivesSeaLevel() {
    var initial = burlington
    initial.destinationAirport = "XXXX"
    var state = SimState(initial: initial)
    var module = WorldModule(navData: sampleDatabase)
    run(&module, &state, steps: 1...1, initial: initial)
    #expect(state.world.environment?.destination == .notInDatabase)
    #expect(state.world.terrainElevationM == 0)
}

struct BrokenDatabase: NavDatabase {
    var identity: NavDataIdentity? { nil }
    func airport(_ ident: String) throws(NavDataError) -> NavAirport? { throw .storage("disk error") }
    func runways(airport: String) throws(NavDataError) -> [NavRunway] { [] }
    func localizers(airport: String) throws(NavDataError) -> [NavILS] { [] }
    func fixes(ident: String) throws(NavDataError) -> [NavFix] { [] }
    func navaids(ident: String) throws(NavDataError) -> [NavNavaid] { [] }
    func waypoints(ident: String) throws(NavDataError) -> [NavWaypoint] { [] }
    func procedures(airport: String, kind: NavProcedureKind?) throws(NavDataError) -> [NavProcedure] { [] }
    func legs(transitionID: Int64) throws(NavDataError) -> [NavProcedureLeg] { [] }
    func airway(_ route: String) throws(NavDataError) -> [NavAirwayFix] { [] }
    func fixes(near center: GeoPoint, radiusNM: Double, kinds: Set<NavFixKind>) throws(NavDataError) -> [NavFix] { [] }
}

@Test func databaseErrorIsKeptInTheEnvironment() {
    var state = SimState(initial: burlington)
    var module = WorldModule(navData: BrokenDatabase())
    run(&module, &state, steps: 1...1)
    #expect(state.world.environment?.destination == .failed(.storage("disk error")))
    #expect(state.world.terrainElevationM == 0)
}

/// Acceptance criterion (QNH): on the ground of the destination an altimeter set to QNH shows the elevation.
@Test func altimeterSetToQNHShowsTheElevationAtTheDestination() {
    var initial = burlington
    initial.aircraft = InitialAircraft(position: GeoPoint(latDeg: 44.4719, lonDeg: -73.1533), altitudeFt: 335)
    var state = SimState(initial: initial)
    var module = WorldModule(navData: sampleDatabase)
    run(&module, &state, steps: 1...1, initial: initial)
    let shown = Atmosphere.altimeterAltitude(pressureAltitudeM: state.world.air.pressureAltitudeM, settingPa: 103_000)
    #expect(abs(shown / Units.metresPerFoot - 335) < 0.01)
    // ISA +20: the air is 20 K warmer than the ISA temperature at its pressure altitude.
    #expect(abs(state.world.air.temperatureK - ISA.temperature(pressureAltitudeM: state.world.air.pressureAltitudeM) - 20) < 1e-9)
}

@Test func valuesAreForTheAircraftPositionOfThePreviousStep() {
    var state = SimState(initial: burlington)
    var module = WorldModule(navData: sampleDatabase)
    run(&module, &state, steps: 1...1)
    let environment = state.world.environment!
    let altitude = 12_000 * Units.metresPerFoot
    #expect(state.world.air == environment.atmosphere.air(altitudeM: altitude))
    #expect(state.world.wind == environment.windProfile.wind(altitudeM: altitude))
    // 12 000 ft is in the middle of the layers 8000 and 16 000 ft.
    let expectedWind = WindProfile(layers: burlington.weather.windLayers).wind(altitudeM: altitude)
    #expect(state.world.wind == expectedWind)
    let variation = MagneticModel.current.declination(
        at: GeoPoint(latDeg: 44.2, lonDeg: -73.4), heightM: altitude, decimalYear: state.world.utc.decimalYear
    )
    #expect(state.world.magneticVariationDeg == variation)
    #expect(state.world.magneticVariationDeg > -16 && state.world.magneticVariationDeg < -12)   // west variation in Vermont

    // The aircraft moves (as E04 will do): the next step uses the new position.
    state.aircraft.altitudeM = 0
    run(&module, &state, steps: 2...2)
    #expect(state.world.wind == WindProfile(layers: burlington.weather.windLayers).wind(altitudeM: 0))
}

@Test func utcTimeOfTheStepCrossesMidnight() {
    var state = SimState(initial: burlington)
    var module = WorldModule(navData: sampleDatabase)
    run(&module, &state, steps: 20_000...20_000)      // 86 000 s + 400 s
    #expect(state.world.utc.date == UTCDate(year: 2026, month: 11, day: 27))
    #expect(state.world.utc.secondsOfDay == 0)
    let snapshot = state.makeSnapshot(context: StepContext(step: 20_000, events: [], initial: burlington))
    #expect(snapshot.utcSecondsOfDay == state.world.utc.secondsOfDay)
}

/// Acceptance criterion: the same input data give the same result.
@Test func sameInputGivesTheSameWorld() {
    func flight() -> [WorldState] {
        var state = SimState(initial: burlington)
        var module = WorldModule(navData: sampleDatabase)
        var states: [WorldState] = []
        for step in UInt64(1)...500 {
            state.aircraft.altitudeM = 3657.6 - Double(step) * 0.2        // a descent
            state.aircraft.position.lonDeg += 0.0001
            module.run(on: &state, context: StepContext(step: step, events: [], initial: burlington))
            states.append(state.world)
        }
        return states
    }
    #expect(flight() == flight())
}
