// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TripTracker",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "TripTracker",
            targets: ["TripTracker"]
        ),
    ],
    targets: [
        .target(
            name: "TripTracker",
            path: "Sources/TripTracker"
        ),
    ]
)
