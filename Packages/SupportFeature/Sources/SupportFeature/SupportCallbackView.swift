import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

public struct SupportCallbackView: View {
    @State private var viewModel: SupportCallbackViewModel

    public init(viewModel: SupportCallbackViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .choosing:
                topicList
            case .queued:
                queuedConfirmation
            case .failed:
                ContentUnavailableView(
                    "Couldn't queue your request",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Something went wrong on the device. Please try again.")
                )
            }
        }
        .navigationTitle("Request a Callback")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var topicList: some View {
        List {
            Section {
                ForEach(SupportCallbackViewModel.topics) { topic in
                    Button {
                        viewModel.selectedTopicID = topic.id
                    } label: {
                        HStack {
                            Label(topic.title, systemImage: topic.icon)
                            Spacer()
                            if viewModel.selectedTopicID == topic.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .accessibilityAddTraits(viewModel.selectedTopicID == topic.id ? [.isSelected] : [])
                }
            } header: {
                Text("What should we call about?")
            } footer: {
                Text("Works offline too — we'll send your request as soon as you're back on the network.")
            }

            Section {
                Button("Request Callback") {
                    viewModel.requestCallback()
                }
                .primaryButton()
                .disabled(viewModel.selectedTopicID == nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    private var queuedConfirmation: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray.and.arrow.up.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("Request queued")
                .font(.title2.bold())
            // Honest copy: queued ≠ delivered. The sync badge on the list
            // shows the request until it actually leaves the device.
            Text("We've saved your request on this phone. It will be sent automatically "
                + "— even if you're offline right now — and we'll call you back "
                + "within one business day of receiving it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .onAppear {
            AccessibilityNotification.Announcement("Callback request queued.").post()
        }
    }
}
