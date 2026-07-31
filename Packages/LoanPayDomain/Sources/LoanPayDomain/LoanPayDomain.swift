import Foundation
// import SwiftUI
// ARCH: ^ deliberately commented out, and it must stay that way. The Domain
// layer describes loans, payments and rules — not how they are drawn. The
// moment SwiftUI leaks in here, every consumer (data layer, CLI tools, test
// hosts) inherits a UI framework dependency, and domain types start growing
// view-convenience members that don't belong to the business. If you feel
// the need to import SwiftUI here, the type you are writing belongs in
// LoanPayFeatureKit or a feature package instead.

// This file intentionally declares nothing. It exists as the package's
// front door: the place where the layering contract above is recorded.
