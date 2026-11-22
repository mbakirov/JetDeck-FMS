// swift-tools-version: 6.2
import PackageDescription

/// Simulation modules in step order. Each module depends only on Kernel and SimCoreContract.
/// A module must not import another module. `make lint-imports` checks this rule.
let modules = ["World", "Sensors", "FMS", "AutoFlight", "FBW", "Aircraft", "Warnings", "Displays"]

var targets: [Target] = [
    .target(name: "SimCoreContract"),
    .target(name: "Kernel", dependencies: ["SimCoreContract"]),
    .target(name: "SnapshotDiff", dependencies: ["SimCoreContract"]),
    .target(
        name: "SimCore",
        dependencies: ["SimCoreContract", "Kernel"] + modules.map { Target.Dependency(stringLiteral: $0) }
    ),
    .executableTarget(name: "simcore-cli", dependencies: ["SimCore", "SnapshotDiff"]),

    .testTarget(name: "SimCoreContractTests", dependencies: ["SimCoreContract"]),
    .testTarget(name: "KernelTests", dependencies: ["Kernel"]),
    .testTarget(name: "SnapshotDiffTests", dependencies: ["SnapshotDiff"]),
    .testTarget(name: "SimCoreTests", dependencies: ["SimCore"]),
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
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
