import SwiftUI

@main
struct LoanPayApp: App {
    // ARCH: the app struct does exactly two things — own the composition
    // root and hand it to the shell. All wiring lives in AppDependencies;
    // all navigation lives in coordinators. If this file grows, something
    // is in the wrong layer.
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
