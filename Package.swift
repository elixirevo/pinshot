// swift-tools-version: 6.0
import PackageDescription
import Foundation

let essentialsPath = ProcessInfo.processInfo.environment["MAC_APP_ESSENTIALS_PATH"] ?? "../tools/library"
let package = Package(
    name: "PinShot",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "PinShot", targets: ["PinShot"]),
               .executable(name: "ScreenshotTests", targets: ["ScreenshotTests"])],
    dependencies: [
        .package(name: "MacAppEssentials", path: essentialsPath),
        .package(path: essentialsPath + "/Integrations/MacAppUpdatesSparkle"),
        .package(path: essentialsPath + "/Integrations/MacAppDiagnosticsSentry")
    ],
    targets: [
        .target(name: "PinShotApp", dependencies: [
            .product(name: "MacAppCore", package: "MacAppEssentials"),
            .product(name: "MacAppSettings", package: "MacAppEssentials"),
            .product(name: "MacAppOnboarding", package: "MacAppEssentials"),
            .product(name: "MacAppMenuBar", package: "MacAppEssentials"),
            .product(name: "MacAppMainMenu", package: "MacAppEssentials"),
            .product(name: "MacAppLifecycle", package: "MacAppEssentials"),
            .product(name: "MacAppUpdatesSparkle", package: "MacAppUpdatesSparkle"),
            .product(name: "MacAppDiagnosticsSentry", package: "MacAppDiagnosticsSentry")
        ], path: "Sources", resources: [.process("Resources")]),
        .executableTarget(name: "PinShot", dependencies: ["PinShotApp"], path: "App"),
        .executableTarget(name: "ScreenshotTests", dependencies: ["PinShotApp"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
