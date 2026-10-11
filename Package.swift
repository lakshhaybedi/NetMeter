// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "NetMeter",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "NetMeter"),
        .testTarget(name: "NetMeterTests", dependencies: ["NetMeter"]),
    ]
)
