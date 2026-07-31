import Foundation
import BackgroundTasks
import LoanPayData

/// Registers and schedules the background drain.
///
/// MODERN (and honest): BGTaskScheduler is OPPORTUNISTIC — unlike Android's
/// WorkManager, which contracts to run enqueued work eventually, iOS treats
/// app refresh as a suggestion it grades on user behavior, charger state
/// and thermal budget. It may run in minutes, hours, or never. That is why
/// this is the THIRD drain trigger, behind connectivity-regain and
/// foregrounding, and why the queue must survive indefinitely without it.
///
/// Debug: pause the app in Xcode and run
///   e -l objc -- (void)[[BGTaskScheduler sharedScheduler]
///     _simulateLaunchForTaskWithIdentifier:@"com.anhvu.loanpay.outbox-refresh"]
/// to force an execution.
enum OutboxBackgroundRefresh {
    static let identifier = "com.anhvu.loanpay.outbox-refresh"

    /// Must be called before the app finishes launching (BGTaskScheduler
    /// requirement), hence from the App initializer.
    static func register(drainer: OutboxDrainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            scheduleNext() // WHY here: refresh tasks are one-shot; re-arm first.
            let drain = Task {
                await drainer.drainNow()
                task.setTaskCompleted(success: true)
            }
            // WHY cancellation instead of racing the deadline: the drainer
            // is cancellation-aware — the in-flight op returns to the
            // queue, and the idempotency key protects the re-send.
            task.expirationHandler = {
                drain.cancel()
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        // Submission fails in Simulator and when refresh is user-disabled —
        // both fine; the foreground triggers carry the load.
        try? BGTaskScheduler.shared.submit(request)
    }
}
