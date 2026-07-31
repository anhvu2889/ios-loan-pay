// swift-tools-version: 6.0
import PackageDescription

// ARCH: a feature package sees Domain (what a payment IS) and FeatureKit
// (how the app draws things) — never Data, never another feature. The app's
// composition root hands it a PaymentRepository; whether that's the mock or
// URLSession is invisible from in here.
let package = Package(
    name: "PaymentFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PaymentFeature", targets: ["PaymentFeature"])
    ],
    dependencies: [
        .package(path: "../LoanPayDomain"),
        .package(path: "../LoanPayFeatureKit"),
    ],
    targets: [
        .target(
            name: "PaymentFeature",
            dependencies: ["LoanPayDomain", "LoanPayFeatureKit"]
        ),
        .testTarget(
            name: "PaymentFeatureTests",
            dependencies: ["PaymentFeature", "LoanPayDomain"]
        ),
    ]
)
