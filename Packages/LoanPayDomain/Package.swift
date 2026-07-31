// swift-tools-version: 6.0
import PackageDescription

// ARCH: The Domain package is the innermost ring: it declares WHAT the app
// does (entities, use cases, repository contracts) and knows nothing about
// HOW (no networking, no persistence, no UI). Every other package points
// inward at this one; this one points at nothing but Foundation.
let package = Package(
    name: "LoanPayDomain",
    // WHY: macOS is listed alongside iOS solely so `swift test` can run this
    // package's suite natively on CI/dev machines without booting a
    // simulator. Domain code is Foundation-only, so it compiles everywhere.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LoanPayDomain", targets: ["LoanPayDomain"])
    ],
    targets: [
        // ARCH: zero dependencies — the compiler enforces the "Domain imports
        // Foundation only" rule better than any code review can.
        .target(name: "LoanPayDomain"),
        .testTarget(name: "LoanPayDomainTests", dependencies: ["LoanPayDomain"]),
    ]
)
