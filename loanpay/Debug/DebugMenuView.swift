#if DEBUG
import SwiftUI
import LoanPayDomain
import LoanPayData

/// The tester's control room: per-endpoint failure injection, simulated
/// latency, and flag overrides. DEBUG-only at the compiler level — this
/// file does not exist in a Release binary, which is the strongest possible
/// guarantee that no App Review build can flip a kill switch.
struct DebugMenuView: View {
    let behavior: MockBehavior
    let flags: RuntimeOverridableFlags

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [MockEndpoint: FailureChoice] = [:]
    @State private var flagStates: [FeatureFlag: Bool] = [:]

    enum FailureChoice: String, CaseIterable, Identifiable {
        case none = "None"
        case offline = "Offline"
        case http500 = "HTTP 500"
        case http401 = "HTTP 401"
        case http404 = "HTTP 404"
        case malformed = "Malformed JSON"
        case flakyHalf = "Flaky 50%"
        case slow3s = "Slow 3s"

        var id: String { rawValue }

        var injected: InjectedFailure? {
            switch self {
            case .none: nil
            case .offline: .offline
            case .http500: .httpStatus(500)
            case .http401: .httpStatus(401)
            case .http404: .httpStatus(404)
            case .malformed: .malformedJSON
            case .flakyHalf: .flaky(rate: 0.5)
            case .slow3s: .slow(seconds: 3)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Backend", selection: environmentBinding) {
                        Text("In-process mock").tag(AppEnvironment.mockInProcess)
                        Text("Localhost server").tag(AppEnvironment.remoteLocalhost)
                    }
                } header: {
                    Text("Environment")
                } footer: {
                    // Honest UX: dependencies are wired once at launch;
                    // pretending a live switch works would leave half the
                    // object graph on the old backend.
                    Text("Takes effect on the next launch. Start the server first: npx json-server db.json --port 3000 (see Scripts/mock-server).")
                }

                Section("Mock backend failures") {
                    ForEach(MockEndpoint.allCases, id: \.self) { endpoint in
                        Picker(endpoint.rawValue, selection: binding(for: endpoint)) {
                            ForEach(FailureChoice.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                            }
                        }
                    }
                }

                Section("Feature flags") {
                    ForEach(FeatureFlag.allCases, id: \.self) { flag in
                        Toggle(flag.rawValue, isOn: flagBinding(for: flag))
                    }
                }
            }
            .navigationTitle("Debug Menu")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            for flag in FeatureFlag.allCases {
                flagStates[flag] = flags.isEnabled(flag)
            }
            for endpoint in MockEndpoint.allCases {
                selections[endpoint] = await choice(for: behavior.failure(for: endpoint))
            }
        }
    }

    private var environmentBinding: Binding<AppEnvironment> {
        Binding(
            get: { AppEnvironment.current() },
            set: { UserDefaults.standard.set($0.rawValue, forKey: AppEnvironment.defaultsKey) }
        )
    }

    private func binding(for endpoint: MockEndpoint) -> Binding<FailureChoice> {
        Binding(
            get: { selections[endpoint] ?? .none },
            set: { choice in
                selections[endpoint] = choice
                Task { await behavior.setFailure(choice.injected, for: endpoint) }
            }
        )
    }

    private func flagBinding(for flag: FeatureFlag) -> Binding<Bool> {
        Binding(
            get: { flagStates[flag] ?? flags.isEnabled(flag) },
            set: { enabled in
                flagStates[flag] = enabled
                flags.setOverride(enabled, for: flag)
            }
        )
    }

    private func choice(for failure: InjectedFailure?) -> FailureChoice {
        switch failure {
        case nil: .none
        case .offline: .offline
        case .httpStatus(401): .http401
        case .httpStatus(404): .http404
        case .httpStatus: .http500
        case .malformedJSON: .malformed
        case .flaky: .flakyHalf
        case .slow: .slow3s
        }
    }
}
#endif
