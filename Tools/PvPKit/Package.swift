// swift-tools-version: 6.0
import PackageDescription

let settings: [SwiftSetting] = [.enableUpcomingFeature("MemberImportVisibility")]

func block(_ name: String, resources: [Resource]? = nil) -> [Target] {
    [
        .target(name: name, swiftSettings: settings),
        .testTarget(name: "\(name)Tests", dependencies: [.target(name: name)], resources: resources, swiftSettings: settings)
    ]
}

let package = Package(
    name: "PvPKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    targets: block("PvPContracts")
        + block("PvPBackend")
        + block("PvPTransportKit")
        + block("PvPMatch", resources: [.copy("Resources")])
        + [.target(name: "PvPSession", swiftSettings: settings)]
        + block("PvPFixtures")
        + block("PvPClient")
        + block("PvPScreen")
)
