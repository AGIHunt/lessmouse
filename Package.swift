// swift-tools-version: 5.9
import PackageDescription

// LessMouseCore holds every testable piece (models, detector, suggestion
// engine, store, SwiftUI views + localized resources). The executable target
// is a thin @main shell so that `swift test` can import the code without
// linking a second main().
let package = Package(
    name: "LessMouse",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LessMouseCore", targets: ["LessMouseCore"])
    ],
    targets: [
        .target(
            name: "LessMouseCore",
            path: "Sources/LessMouseCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "LessMouse",
            dependencies: ["LessMouseCore"],
            path: "Sources/LessMouse"
        ),
        .testTarget(
            name: "LessMouseTests",
            dependencies: ["LessMouseCore"],
            path: "Tests/LessMouseTests"
        ),
    ]
)
