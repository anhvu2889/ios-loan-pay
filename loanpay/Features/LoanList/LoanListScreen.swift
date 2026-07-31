import SwiftUI
import LoanPayDomain
import LoanPayFeatureKit

struct LoanListScreen: View {
    @Bindable var viewModel: LoanListViewModel
    let onShowDetail: (LoanID) -> Void
    let onShowDebugMenu: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StateContainer(state: displayState, onRetry: { Task { await viewModel.retry() } }) {
            loadedList
        }
        .overlay {
            // Offline gets its own furniture: it is the ONE failure a user
            // can fix themselves, so the screen says how.
            if case .failed(.offline) = viewModel.state {
                ContentUnavailableView {
                    Label("You're offline", systemImage: "wifi.slash")
                } description: {
                    Text("Your loans will load as soon as you're back on the network.")
                } actions: {
                    Button("Try Again") { Task { await viewModel.retry() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.listRetryButton)
                }
                .background()
            }
        }
        .navigationTitle("My Loans")
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .principal) {
                // The debug back door hides in plain sight: triple-tap the
                // title. Compiled out of Release entirely.
                Text("My Loans")
                    .font(.headline)
                    .onTapGesture(count: 3, perform: onShowDebugMenu)
            }
            #endif
        }
        .task {
            await viewModel.loadInitial()
        }
        .onDisappear {
            viewModel.cancelOngoingWork()
        }
        .modifier(SearchModifier(viewModel: viewModel))
    }

    private var displayState: ContentDisplayState {
        switch viewModel.state {
        case .loading:
            // The list renders its own skeleton (redacted real rows), so
            // the container is told "content" during loading too.
            return .content
        case .loaded:
            return .content
        case .empty:
            return .empty(
                title: "No loans yet",
                message: "When you finance a device, it will show up here."
            )
        case .failed(.offline):
            return .content // rendered by the dedicated offline overlay
        case .failed(let error):
            return .error(message: error.userMessage, isRetryable: error.isRetryable)
        }
    }

    @ViewBuilder
    private var loadedList: AnyView {
        AnyView(
            List {
                if viewModel.state == .loading {
                    skeletonRows
                } else if let results = viewModel.searchResults {
                    searchResultRows(results)
                } else {
                    PortfolioSummaryHeader(summary: viewModel.summary)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    sectionedRows
                    paginationFooter
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.loanList)
            .refreshable {
                await viewModel.refresh()
            }
            // WHY value-based animation instead of withAnimation at every
            // mutation site: the trigger is "the visible content changed",
            // and reduce-motion turns it off wholesale.
            .animation(reduceMotion ? nil : .default, value: viewModel.sections)
            .animation(reduceMotion ? nil : .default, value: viewModel.searchResults)
        )
    }

    private var skeletonRows: some View {
        // Skeleton = REAL rows, redacted. The shimmering placeholder shares
        // layout code with the loaded state, so it can never drift into a
        // different-looking loading screen.
        ForEach(0..<6, id: \.self) { index in
            LoanRowView(
                loan: PreviewFixtures.activeLoan,
                onSelect: {},
                onRequestCallback: {}
            )
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
        }
    }

    private var sectionedRows: some View {
        ForEach(viewModel.sections) { section in
            Section {
                ForEach(section.loans) { loan in
                    row(for: loan)
                        .onAppear { viewModel.rowAppeared(loan) }
                }
            } header: {
                // Plain-style list headers pin while scrolling — the
                // "sticky" grouping that keeps status context on screen.
                Text(sectionTitle(section.status))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func searchResultRows(_ results: [Loan]) -> some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(results) { loan in
                    row(for: loan)
                }
            }
        }
    }

    private func row(for loan: Loan) -> some View {
        LoanRowView(
            loan: loan,
            onSelect: { onShowDetail(loan.id) },
            onRequestCallback: { viewModel.requestCallback(for: loan) }
        )
    }

    @ViewBuilder
    private var paginationFooter: some View {
        switch viewModel.paginationFooter {
        case .hidden:
            EmptyView()
        case .loadingMore:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowSeparator(.hidden)
        case .endOfList:
            Text("That's every loan on file.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        }
    }

    private func sectionTitle(_ status: LoanStatus) -> String {
        switch status {
        case .active: "Active"
        case .overdue: "Needs attention"
        case .paidOff: "Paid off"
        case .unknown: "Other"
        }
    }
}

/// Search is flag-gated: the modifier exists so the `if` lives in ONE place
/// and the screen body stays legible.
private struct SearchModifier: ViewModifier {
    @Bindable var viewModel: LoanListViewModel

    func body(content: Content) -> some View {
        if viewModel.isSearchEnabled {
            content
                .searchable(text: $viewModel.searchText, prompt: "Search device models")
                .searchSuggestions {
                    ForEach(viewModel.searchSuggestions, id: \.self) { model in
                        Text(model).searchCompletion(model)
                    }
                }
        } else {
            content
        }
    }
}
