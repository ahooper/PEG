// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PEG",
    platforms: [
        .macOS(.v15),
        // Array 'indices(of:)' is only available in macOS 15.0 or newer
        // Conformance of 'RangeSet<Bound>.Ranges' to 'BidirectionalCollection' is only available in macOS 15.0 or newer
        // Conformance of 'RangeSet<Bound>.Ranges' to 'Sequence' is only available in macOS 15.0 or newer
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PEG",
            targets: ["PEG"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PEG",
            swiftSettings: [
                //.enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "PEGTests",
            dependencies: ["PEG"],
            swiftSettings: [
                //.enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
