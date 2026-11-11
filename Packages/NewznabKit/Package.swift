// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NewznabKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "NewznabKit", targets: ["NewznabKit"]),
    ],
    targets: [
        // Newznab indexer API: request building, RSS/error parsing, NZB download validation.
        .target(name: "NewznabKit"),
        .testTarget(
            name: "NewznabKitTests",
            dependencies: ["NewznabKit"]
        ),
    ]
)
