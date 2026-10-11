// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirNRGNeo",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AirNRGNeo", targets: ["NRGExtractorApp"]),
        .executable(name: "nrg2wav", targets: ["nrg2wav"]),
    ],
    targets: [
        .target(name: "NRGCore"),
        .executableTarget(name: "nrg2wav", dependencies: ["NRGCore"]),
        .executableTarget(name: "NRGExtractorApp", dependencies: ["NRGCore"]),
    ]
)
