// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TripleSpaceTranslatorApp",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "TripleSpaceTranslatorApp",
            targets: ["TripleSpaceTranslatorApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TripleSpaceTranslatorApp",
            path: "Sources/TripleSpaceTranslatorApp"
        )
    ]
)
