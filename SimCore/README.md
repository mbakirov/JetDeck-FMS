# SimCore

The simulation core of JetDeck FMS. It is a Swift package without UI code. It runs the simulation with a fixed step of 20 ms (50 Hz).

The application sends `InputEvent` values. The core returns `Snapshot` values. The contract is in `Sources/SimCoreContract/SimCoreContract.swift`.

```swift
import SimCore

let engine = SimEngine(initial: initialConditions)
let runner = SimRunner(core: engine) { snapshot in /* draw */ }
runner.start()
engine.send(.fcu(.knobPulled(.altitude)))   // applied in the next step
runner.pause()                              // the simulation time stops
let recording = engine.recording()          // initial conditions and all events
```

## Layers

```
simcore-cli ──► SimCore ──► World, Sensors, FMS, AutoFlight, FBW, Aircraft, Warnings, Displays
                   │                              │
                   └──────────► Kernel ◄──────────┘
                                   │
SnapshotDiff ──────────────► SimCoreContract
```

- A simulation module imports only `Kernel` and `SimCoreContract`. `make lint-imports` checks this rule.
- `Kernel` has the state bus `SimState`. Each section of the state has one writer.
- `Kernel/Earth` has the functions of the world that all modules use: WGS-84 geodesy (on `CGeodesic`, GeographicLib-C), the ISA atmosphere with QNH, air data, wind and the WMM2025 magnetic model. See `Docs/world.md`.
- The step order is fixed: input, World, Sensors, FMS, AutoFlight, FBW, Aircraft, Warnings, Displays, snapshot.

## Commands

Run `make help` in the repository root. `make check` is the full check.

## Recordings and replay

A recording has the initial conditions and the list of input events with step numbers. A replay gives the same snapshots as the original flight.

```
swift run -c release simcore-cli replay <recording.json> --out a.jsonl --every 50
swift run -c release simcore-cli diff expected.jsonl actual.jsonl --tolerance 0.001
```

`diff` returns exit code 1 when the files are different.

## Reference recordings

A reference recording is a directory in `Tests/GoldenTests/Goldens/` with two files:

- `recording.json` — the recording.
- `snapshots.jsonl` — the reference snapshots, one on each line.

To add a reference recording:

1. Make the directory and put `recording.json` in it.
2. Run `make golden-update`. It writes `snapshots.jsonl` for all recordings.
3. Run `make replay-goldens`.

Run `make golden-update` after each intended change of the simulation results. Examine the change of `snapshots.jsonl` in the diff before the commit.

## Step time

`make bench` runs 30 000 steps and writes `build/reports/step-timing.json` and `step-timing.md` (mean, p50, p99, max). The budget of one step is 20 000 µs.

## Navigation database

The core reads the navigation data through the protocol `NavDatabase` (target `Kernel`). The file is SQLite, made from the FAA CIFP by `navdb-cli convert`. See `Docs/navdb.md` in the repository root.

```swift
import NavDB
import NavDBUpdate
import SimCore

let store = NavDBStore(bundledPath: bundledURL.path, directory: applicationSupport.appendingPathComponent("NavDB"))
let active = try store.openActive()                       // the downloaded database or the bundled one
let engine = SimEngine(initial: initialConditions, navData: active.reader)
active.reader.cycle?.ident                                // "2611", for the A/C STATUS page

let updater = NavDBUpdater(manifestURL: manifestURL, store: store)
_ = try await updater.update()                            // used from the next scenario
```

```
make navdb-cycle                       # download, convert, verify, measure, manifest (needs network)
swift run -c release navdb-cli convert --cifp FAACIFP18 --out navdb.sqlite --report report.json
swift run -c release simcore-cli replay recording.json --navdb navdb.sqlite
```

