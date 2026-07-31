import SwiftUI
import LoanPayData

@main
struct LoanPayApp: App {
    // ARCH: the app struct does exactly two things — own the composition
    // root and hand it to the shell. All wiring lives in AppDependencies;
    // all navigation lives in coordinators. If this file grows, something
    // is in the wrong layer.
    @State private var dependencies: AppDependencies

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let dependencies = AppDependencies()
        _dependencies = State(initialValue: dependencies)
        // BGTaskScheduler demands registration before launch completes.
        OutboxBackgroundRefresh.register(drainer: dependencies.outboxDrainer)
    }

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Foreground drain: the cheapest, most reliable trigger.
                Task { await dependencies.outboxDrainer.drainNow() }
            case .background:
                OutboxBackgroundRefresh.scheduleNext()
            default:
                break
            }
        }
    }
}
