// swift-tools-version: 6.2
import PackageDescription

/// Simulation modules in step order. Each module depends only on Kernel and SimCoreContract.
/// A module must not import another module. `make lint-imports` checks this rule.
let modules = ["World", "Sensors", "FMS", "AutoFlight", "FBW", "Aircraft", "Warnings", "Displays"]

var targets: [Target] = [
    .target(name: "SimCoreContract"),
    // Geodesic routines of GeographicLib-C (MIT). Only Kernel uses them. See Sources/CGeodesic/README.md.
    .target(name: "CGeodesic", exclude: ["README.md", "LICENSE.txt"]),
    .target(name: "Kernel", dependencies: ["SimCoreContract", "CGeodesic"]),
    .target(name: "SnapshotDiff", dependencies: ["SimCoreContract"]),
    .target(
        name: "SimCore",
        dependencies: ["SimCoreContract", "Kernel"] + modules.map { Target.Dependency(stringLiteral: $0) }
    ),
    .executableTarget(name: "simcore-cli", dependencies: ["SimCore", "SnapshotDiff", "NavDB", "Kernel"]),

    // Navigation database (E02). The converter and the parser run at build time and are not in the application.
    .target(name: "ARINC424"),
    .target(name: "NavDB", dependencies: ["Kernel", "SimCoreContract"]),
    .target(name: "NavDBBuilder", dependencies: ["ARINC424", "NavDB", "Kernel", "SimCoreContract"]),
    .target(name: "NavDBUpdate", dependencies: ["NavDB", "Kernel", "SimCoreContract"]),
    .executableTarget(name: "navdb-cli", dependencies: ["NavDBBuilder", "NavDBUpdate", "NavDB", "SimCoreContract"]),

    .testTarget(name: "SimCoreContractTests", dependencies: ["SimCoreContract"]),
    .testTarget(name: "KernelTests", dependencies: ["Kernel"]),
    .testTarget(name: "SnapshotDiffTests", dependencies: ["SnapshotDiff"]),
    .testTarget(name: "ARINC424Tests", dependencies: ["ARINC424"]),
    .testTarget(name: "NavDBTests", dependencies: ["NavDB", "NavDBBuilder", "Kernel"]),
    .testTarget(name: "NavDBBuilderTests", dependencies: ["NavDBBuilder", "NavDB", "ARINC424", "Kernel"]),
    .testTarget(name: "NavDBUpdateTests", dependencies: ["NavDBUpdate", "NavDB", "NavDBBuilder", "Kernel"]),
    .testTarget(name: "SimCoreTests", dependencies: ["SimCore", "Kernel", "FMS", "Displays"]),
    .testTarget(
        name: "GoldenTests",
        dependencies: ["SimCore", "SnapshotDiff"],
        resources: [.copy("Goldens")]
    ),
]

for module in modules {
    targets.append(.target(name: module, dependencies: ["Kernel", "SimCoreContract"]))
    targets.append(.testTarget(name: "\(module)Tests", dependencies: [.init(stringLiteral: module), "Kernel"]))
}

let package = Package(
    name: "SimCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SimCore", targets: ["SimCore"]),
        .library(name: "SnapshotDiff", targets: ["SnapshotDiff"]),
        .executable(name: "simcore-cli", targets: ["simcore-cli"]),
        .library(name: "NavDB", targets: ["NavDB", "NavDBUpdate"]),
        .executable(name: "navdb-cli", targets: ["navdb-cli"]),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
