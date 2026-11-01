// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpineSaver",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpineSaver", targets: ["SpineSaver"]),
        .executable(name: "SpineSaverSelfTest", targets: ["SpineSaverSelfTest"])
    ],
    targets: [
        .target(
            name: "SpineSaverCore",
            path: "Sources/SpineSaverCore"
        ),
        .executableTarget(
            name: "SpineSaver",
            dependencies: ["SpineSaverCore"],
            path: "Sources/SpineSaver",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Charts"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "SpineSaverSelfTest",
            dependencies: ["SpineSaverCore"],
            path: "Sources/SpineSaverSelfTest"
        ),
        .testTarget(
            name: "SpineSaverTests",
            dependencies: ["SpineSaverCore"],
            path: "Tests/SpineSaverTests"
        )
    ]
)
