// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SystemMonitorCore", targets: ["SystemMonitorCore"]),
        .executable(name: "drivemon", targets: ["drivemon"]),
        .executable(name: "SystemMonitorApp", targets: ["SystemMonitorApp"]),
    ],
    targets: [
        .target(
            name: "CPower",
            linkerSettings: [
                .linkedLibrary("IOReport"),
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "powermon",
            dependencies: ["CPower"]
        ),
        .target(
            name: "SystemMonitorCore",
            dependencies: ["CPower"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("DiskArbitration"),
            ]
        ),
        .executableTarget(
            name: "drivemon",
            dependencies: ["SystemMonitorCore"]
        ),
        .executableTarget(
            name: "SystemMonitorApp",
            dependencies: ["SystemMonitorCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
