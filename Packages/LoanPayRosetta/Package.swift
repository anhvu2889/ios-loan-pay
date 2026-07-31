// swift-tools-version: 6.0
import PackageDescription

// ARCH: a TEST-ONLY package. The suite of record is Swift Testing; this
// target re-states 12 representative tests in XCTest so an engineer fluent
// in one framework can read the other side by side — a Rosetta stone, not
// a second source of truth. If a behavior changes, fix the Swift Testing
// original first; the translation follows.
let package = Package(
    name: "LoanPayRosetta",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(path: "../LoanPayDomain"),
        .package(path: "../LoanPayData"),
    ],
    targets: [
        .testTarget(
            name: "LoanPayXCTestRosetta",
            dependencies: ["LoanPayDomain", "LoanPayData"]
        )
    ]
)
