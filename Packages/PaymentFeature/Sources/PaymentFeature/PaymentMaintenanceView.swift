import SwiftUI
import LoanPayFeatureKit

/// The kill switch's face: deliberate downtime, honestly labeled.
struct PaymentMaintenanceView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Payments are paused", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("We're doing maintenance on payments right now. Your loans are unaffected — please try again a little later.")
        }
        .onAppear {
            // VoiceOver hears WHY the screen has no pay button, instead of
            // discovering an inexplicably empty sheet.
            AccessibilityNotification.Announcement(
                "Payments are paused for maintenance. Please try again later."
            ).post()
        }
    }
}

#Preview {
    PaymentMaintenanceView()
}
