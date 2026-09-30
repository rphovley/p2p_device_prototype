// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ble-smoke-test",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../shared")
    ],
    targets: [
        .executableTarget(
            name: "ble-smoke-test",
            dependencies: [
                .product(name: "PairingKit", package: "shared")
            ]
        )
    ]
)
