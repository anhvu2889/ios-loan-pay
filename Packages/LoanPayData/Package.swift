// swift-tools-version: 6.0
import PackageDescription

// ARCH: Data depends on Domain and NOTHING else — it implements Domain's
// repository contracts and translates the outside world (wire DTOs,
// transport errors) into domain language at this boundary. No UI framework
// ever appears here.
let package = Package(
    name: "LoanPayData",
    // WHY: macOS is listed solely so `swift test` runs natively without a
    // simulator; the package itself is iOS-first.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LoanPayData", targets: ["LoanPayData"])
    ],
    dependencies: [
        .package(path: "../LoanPayDomain")
    ],
    targets: [
        .target(
            name: "LoanPayData",
            dependencies: ["LoanPayDomain"],
            resources: [
                // WHY .process for fixture JSON: the mock repositories are
                // "the backend" during development, and their dataset ships
                // as a bundle resource rather than being hardcoded in Swift —
                // editing the world means editing JSON, exactly like the
                // real API.
                .process("Resources")
            ]
        ),
        .testTarget(name: "LoanPayDataTests", dependencies: ["LoanPayData", "LoanPayDomain"]),
    ]
)
