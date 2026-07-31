// swift-tools-version: 6.0
import PackageDescription

// ARCH: FeatureKit is the shared presentation vocabulary — typed routes,
// the feature registry seam, and the design system. It depends ONLY on
// Domain: it may know what a Loan is, never where it came from. Feature
// packages depend on FeatureKit + Domain; none of them may depend on each
// other, and this package is what makes that possible.
let package = Package(
    name: "LoanPayFeatureKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "LoanPayFeatureKit", targets: ["LoanPayFeatureKit"])
    ],
    dependencies: [
        .package(path: "../LoanPayDomain")
    ],
    targets: [
        .target(name: "LoanPayFeatureKit", dependencies: ["LoanPayDomain"])
    ]
)
