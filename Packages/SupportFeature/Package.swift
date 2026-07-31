// swift-tools-version: 6.0
import PackageDescription

// ARCH: same contract as every feature package — Domain + FeatureKit only,
// no Data, no sibling features. Support writes go through the OutboxEnqueuing
// seam; this package neither knows nor cares that a file-backed queue and a
// drainer exist behind it.
let package = Package(
    name: "SupportFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SupportFeature", targets: ["SupportFeature"])
    ],
    dependencies: [
        .package(path: "../LoanPayDomain"),
        .package(path: "../LoanPayFeatureKit"),
    ],
    targets: [
        .target(
            name: "SupportFeature",
            dependencies: ["LoanPayDomain", "LoanPayFeatureKit"]
        ),
        .testTarget(
            name: "SupportFeatureTests",
            dependencies: ["SupportFeature", "LoanPayDomain"]
        ),
    ]
)
