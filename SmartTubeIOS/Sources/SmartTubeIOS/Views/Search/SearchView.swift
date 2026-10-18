import SmartTubeIOSCore
import SwiftUI

// MARK: - SearchView
//
// The system search field (`.searchable`) with live suggestions on iPhone, iPad and Mac; tvOS keeps its
// text field. Idle shows recent searches and topics; loading, results, "no results" and the search error
// (A5) are separate states of `SearchViewModel.phase`. Mirrors the Android `SearchTagsActivity`.

public struct SearchView: View {
    @Environment(SearchViewModel.self) private var vm
    @Environment(\.innerTubeAPI) private var api
    @Environment(SettingsStore.self) private var store
    @State private var selectedVideo: Video?
    @State private var channelDestination: ChannelDestination?
    @State private var showFilters = false
    #if os(macOS)
    @State private var showFiltersSheet = false
    @State private var isSearchVisible = false
    #endif
    @FocusState private var isSearchFocused: Bool
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {}

    public var body: some View {
        searchPresentation
            #if !os(iOS)
        // tvOS and macOS push the player in this stack, like a card click; iOS presents it through PlayerRouter.
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
            #endif
            .navigationDestination(item: $channelDestination) { dest in
                ChannelView(channelId: dest.channelId, api: api)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
                guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
                channelDestination = ChannelDestination(channelId: channelId)
            }
            .task(id: vm.query) { await vm.updateSuggestions(for: vm.query) }
            // Clearing the field (its clear button, Cancel, or the search tab's close) returns to recent searches.
            .onChange(of: vm.query) { _, query in
                if query.isEmpty { vm.clearResults() }
            }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            tvSearchBar
            #endif
            activeFilters
            switch vm.phase {
            case .idle: idleList
            case .loading: loadingView
            case .results: resultsView
            case .noResults: noResultsView
            case .failed: failedView
            }
        }
        .navigationTitle(Text("Search", bundle: .module))
    }

    private var searchControls: some View {
        #if os(tvOS)
        searchContent
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showFilters) { filterSheet }
        #else
        searchContent
            .modifier(SearchField(isFocused: $isSearchFocused) { suggestionRows })
            .toolbar {
                ToolbarItem(placement: .primaryAction) { filterButton }
            }
        #endif
    }

    private var searchPresentation: some View {
        #if os(macOS)
        searchControls
            // Menu actions have no stable toolbar anchor (the toolbar may be hidden or the item in overflow).
            .focusedSceneValue(\.searchFiltersAction, filtersMenuAction)
            .sheet(isPresented: $showFiltersSheet) { filterSheet }
            .onAppear { isSearchVisible = true }
            .onDisappear { isSearchVisible = false }
        #else
        searchControls
        #endif
    }

    private func run(_ query: String) {
        vm.query = query
        vm.search()
        isSearchFocused = false
    }

    // MARK: - Filters

    #if os(macOS)
    private var filtersMenuAction: (() -> Void)? {
        // Swift 6.4 fails to type-check the actor-isolated method reference in a method-or-nil ternary.
        guard isSearchVisible else { return nil }
        return { presentFiltersFromMenu() }
    }

    private func presentFiltersFromMenu() {
        // An open popover already exposes the filters and may contain an unapplied draft.
        guard !showFilters, !showFiltersSheet else { return }
        showFiltersSheet = true
    }
    #endif

    #if !os(tvOS)
    private var filterButton: some View {
        Button {
            showFilters = true
        } label: {
            Label {
                Text("Search filters", bundle: .module)
            } icon: {
                Image(systemName: vm.filter.isDefault ? AppSymbol.channelFilter : AppSymbol.channelFilterActive)
            }
        }
        .accessibilityIdentifier(AccessibilityID.searchFilterButton)
        // A sheet in a compact width (iPhone), a popover anchored to the button on iPad and Mac.
        .popover(isPresented: $showFilters) { filterSheet }
    }
    #endif

    private var filterSheet: some View {
        SearchFilterSheet(current: vm.filter) { newFilter in
            vm.applyFilter(newFilter)
        }
        #if os(macOS)
        .frame(minWidth: 340, minHeight: 520)
        #elseif os(iOS)
        .frame(
            minWidth: horizontalSizeClass == .regular ? 340 : nil,
            minHeight: horizontalSizeClass == .regular ? 560 : nil)
        #endif
    }

    /// Removable chips for the filters that are on, above every state but idle.
    @ViewBuilder
    private var activeFilters: some View {
        let filter = vm.filter
        if !filter.isDefault, vm.phase != .idle {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: VFSpace.s8) {
                    if filter.sortOrder != .relevance {
                        FilterChip(label: LocalizedStringKey(filter.sortOrder.label)) {
                            var updated = filter
                            updated.sortOrder = .relevance
                            vm.applyFilter(updated)
                        }
                    }
                    if filter.uploadDate != .anytime {
                        FilterChip(label: LocalizedStringKey(filter.uploadDate.label)) {
                            var updated = filter
                            updated.uploadDate = .anytime
                            vm.applyFilter(updated)
                        }
                    }
                    if filter.type != .any {
                        FilterChip(label: LocalizedStringKey(filter.type.label)) {
                            var updated = filter
                            updated.type = .any
                            vm.applyFilter(updated)
                        }
                    }
                    if filter.duration != .any {
                        FilterChip(label: LocalizedStringKey(filter.duration.label)) {
                            var updated = filter
                            updated.duration = .any
                            vm.applyFilter(updated)
                        }
                    }
                }
                .padding(.horizontal, VFSpace.s16)
                .padding(.vertical, VFSpace.s8)
            }
        }
    }

    // MARK: - Idle: recent searches and topics

    private var idleList: some View {
        List {
            if !vm.history.isEmpty {
                Section {
                    ForEach(vm.history) { entry in
                        historyRow(entry.query)
                    }
                } header: {
                    HStack {
                        Text("Recent", bundle: .module)
                        Spacer()
                        Button(role: .destructive) {
                            vm.clearHistory()
                        } label: {
                            Text("Clear History", bundle: .module)
                        }
                        .font(.subheadline)
                        .accessibilityIdentifier(AccessibilityID.searchHistoryClearAll)
                    }
                } footer: {
                    Text(
                        "Search history stays on this device, up to 50 searches. Clearing it does not change your watch history.",
                        bundle: .module)
                }
            }
            Section {
                ForEach(vm.suggestions, id: \.self) { topic in
                    HStack(spacing: VFSpace.s12) {
                        Button {
                            run(topic)
                        } label: {
                            rowLabel(topic, symbol: AppSymbol.search)
                        }
                        .buttonStyle(.plain)
                        #if !os(tvOS)
                        fillInButton(topic)
                        #endif
                    }
                }
            } header: {
                Text("Recommended", bundle: .module)
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        .headerProminence(.increased)
        .scrollDismissesKeyboard(.immediately)
        #endif
        .accessibilityIdentifier(AccessibilityID.searchSuggestionsContainer)
    }

    private func historyRow(_ query: String) -> some View {
        HStack(spacing: VFSpace.s12) {
            Button {
                run(query)
            } label: {
                rowLabel(query, symbol: AppSymbol.clock)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.searchHistory(query))
            #if !os(tvOS)
            fillInButton(query)
            Button {
                vm.removeHistoryEntry(query)
            } label: {
                Image(systemName: AppSymbol.xmark)
                    .frame(minWidth: Self.rowButtonSize, minHeight: Self.rowButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Remove \(query) from history", bundle: .module))
            #endif
        }
    }

    private func rowLabel(_ text: String, symbol: String) -> some View {
        Label {
            Text(verbatim: text)  // verbatim: a search query or suggestion
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowButtonSize, alignment: .leading)
        .contentShape(Rectangle())
    }

    #if !os(tvOS)
    /// Puts the text in the field without searching, so it can be refined.
    private func fillInButton(_ text: String) -> some View {
        Button {
            vm.query = text
        } label: {
            Image(systemName: AppSymbol.searchCompletion)
                .frame(minWidth: Self.rowButtonSize, minHeight: Self.rowButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("Put \(text) in the search field", bundle: .module))
    }
    #endif

    /// The platform's minimum hit area: touch on iPhone and iPad, pointer on the Mac, focus on Apple TV.
    static var rowButtonSize: CGFloat {
        #if os(macOS)
        VFTarget.pointer
        #elseif os(tvOS)
        VFTarget.tv
        #else
        VFTarget.touch
        #endif
    }

    // MARK: - Suggestions while typing

    /// Matching recent searches first, then live suggestions; nothing once the text is the submitted query.
    @ViewBuilder
    private var suggestionRows: some View {
        let text = vm.query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty, text != vm.submittedQuery {
            let recent = vm.filteredHistory.map(\.query)
            ForEach(recent, id: \.self) { query in
                suggestionRow(query, symbol: AppSymbol.clock)
            }
            ForEach(vm.suggestions.filter { !recent.contains($0) }, id: \.self) { suggestion in
                suggestionRow(suggestion, symbol: AppSymbol.search)
            }
        }
    }

    @ViewBuilder
    private func suggestionRow(_ text: String, symbol: String) -> some View {
        #if os(macOS)
        // The Mac list is keyboard driven: arrows pick a row, Return searches it.
        Label(text, systemImage: symbol)
            .searchCompletion(text)
            .accessibilityIdentifier(AccessibilityID.searchSuggestion(text))
        #else
        HStack(spacing: VFSpace.s12) {
            Button {
                run(text)
            } label: {
                rowLabel(text, symbol: symbol)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.searchSuggestion(text))
            #if !os(tvOS)
            fillInButton(text)
            #endif
        }
        #endif
    }
}

// MARK: - Loading, results, no results, error

extension SearchView {

    private var loadingView: some View {
        ProgressView {
            Text("Searching for \"\(vm.submittedQuery ?? "")\"…", bundle: .module)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsView: some View {
        let hideShorts = store.settings.hideShorts
        let hideLiveShorts = store.settings.hideLiveShorts
        let hideVideoPremieres = store.settings.hideVideoPremieres
        let displayResults = vm.results
            .filter { !hideShorts || !$0.isShort }
            .filter { !hideLiveShorts || !($0.isLive && $0.isShort) }
            .filter { !hideVideoPremieres || !$0.isUpcoming }
        return ScrollView {
            VideoGridSection(
                videos: displayResults,
                onSelect: { video in
                    let captured = displayResults
                    Task { @MainActor in
                        // Playing a result makes the visible list the queue.
                        await CurrentQueueStore.shared.replaceAll(with: captured)
                        let startIdx = captured.firstIndex(where: { $0.id == video.id }) ?? 0
                        let toPlay = await CurrentQueueStore.shared.videoAt(index: startIdx) ?? video
                        #if os(iOS)
                        playerRouter.open(video: toPlay, api: api)
                        #else
                        selectedVideo = toPlay
                        #endif
                    }
                },
                loadMore: vm.loadMore
            )
            if vm.error != nil {
                // A failed next page keeps the results above it.
                VStack(spacing: VFSpace.s8) {
                    Text("Couldn't load more results.", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        vm.retry()
                    } label: {
                        Text("Try Again", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(AccessibilityID.searchRetryButton)
                }
                .frame(maxWidth: .infinity)
                .padding(VFSpace.s16)
            } else if vm.isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(VFSpace.s16)
            }
        }
        .accessibilityIdentifier(AccessibilityID.searchResults)
        #if os(iOS)
        .scrollDismissesKeyboard(.immediately)
        #endif
    }

    @ViewBuilder
    private var noResultsView: some View {
        let query = vm.submittedQuery ?? ""
        Group {
            if vm.filter.isDefault {
                ContentUnavailableView.search(text: query)
            } else {
                ContentUnavailableView {
                    Label {
                        Text("No results for \"\(query)\"", bundle: .module)
                    } icon: {
                        Image(systemName: AppSymbol.search)
                    }
                } description: {
                    Text("Nothing matches with these filters. Try another query or clear the filters.", bundle: .module)
                } actions: {
                    Button {
                        vm.applyFilter(.default)
                    } label: {
                        Text("Clear Filters", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.searchNoResults)
    }

    /// A5: the request failed, which is not the same as no matches. Query and filters stay as they were.
    private var failedView: some View {
        ContentUnavailableView {
            Label {
                Text("Couldn't Search", bundle: .module)
            } icon: {
                Image(systemName: AppSymbol.warning)
            }
        } description: {
            VStack(spacing: VFSpace.s4) {
                Text("The service didn't respond. Your query and filters are kept.", bundle: .module)
                if let error = vm.error {
                    Text(verbatim: error.localizedDescription)  // verbatim: system error text
                        .font(.footnote)
                }
            }
        } actions: {
            Button {
                vm.retry()
            } label: {
                Text("Try Again", bundle: .module)
            }
            .buttonStyle(.vfProminent)
            .accessibilityIdentifier(AccessibilityID.searchRetryButton)
        }
        .accessibilityIdentifier(AccessibilityID.searchFailed)
    }

    // MARK: - tvOS field

    #if os(tvOS)
    private var tvSearchBar: some View {
        @Bindable var vm = vm
        return HStack(spacing: VFSpace.s16) {
            Image(systemName: AppSymbol.search)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(String(localized: "Search YouTube", bundle: .module), text: $vm.query)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityIdentifier(AccessibilityID.searchBar)
                .onSubmit { run(vm.query) }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                } label: {
                    Image(systemName: AppSymbol.xmarkCircle)
                }
                .accessibilityLabel(Text("Clear", bundle: .module))
                .accessibilityIdentifier(AccessibilityID.searchClearButton)
            }
            Button {
                showFilters = true
            } label: {
                Image(systemName: vm.filter.isDefault ? AppSymbol.channelFilter : AppSymbol.channelFilterActive)
            }
            .accessibilityLabel(Text("Search filters", bundle: .module))
            .accessibilityIdentifier(AccessibilityID.searchFilterButton)
        }
        .padding(.horizontal, VFMargin.tvHorizontal)
        .padding(.vertical, VFSpace.s16)
    }
    #endif
}

// MARK: - SearchField

#if !os(tvOS)
/// `.searchable` with the platform placement: always visible under the title on iOS 18–25, the system
/// position on iOS 26+ (bottom on iPhone, the search tab), the window toolbar on the Mac.
private struct SearchField<Suggestions: View>: ViewModifier {
    let isFocused: FocusState<Bool>.Binding
    @ViewBuilder let suggestions: () -> Suggestions
    @Environment(SearchViewModel.self) private var vm

    func body(content: Content) -> some View {
        @Bindable var vm = vm
        content
            .searchable(text: $vm.query, placement: placement, prompt: Text("Search YouTube", bundle: .module))
            .searchSuggestions { suggestions() }
            .onSubmit(of: .search) { vm.search() }
            // Keep filters reachable during search and let a picked suggestion dismiss the keyboard.
            .searchFocused(isFocused)
            .searchPresentationToolbarBehavior(.avoidHidingContent)
    }

    private var placement: SearchFieldPlacement {
        #if os(iOS)
        if #available(iOS 26, *) { return .automatic }
        return .navigationBarDrawer(displayMode: .always)
        #else
        return .toolbar
        #endif
    }
}

#endif

// MARK: - FilterChip

struct FilterChip: View {
    /// Accent wash behind the chip. The label stays `.primary`: accent text on its own wash drops under 4.5:1.
    static let fillOpacity = 0.15

    let label: LocalizedStringKey
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: VFSpace.s4) {
            Text(label, bundle: .module)
                .font(.subheadline)
            // The button itself is the platform minimum (padding the capsule would not grow it); on Apple TV
            // the borderless style keeps the system focus effect.
            Button(action: onRemove) {
                Image(systemName: AppSymbol.xmark)
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: SearchView.rowButtonSize, minHeight: SearchView.rowButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
            .accessibilityLabel(Text("Remove filter", bundle: .module))
        }
        .padding(.leading, VFSpace.s12)
        .background(.tint.opacity(Self.fillOpacity), in: Capsule())
        .foregroundStyle(.primary)
    }
}

// MARK: - SearchFilterSheet

struct SearchFilterSheet: View {
    let current: SearchFilter
    let onApply: (SearchFilter) -> Void

    @State private var draft: SearchFilter
    @Environment(\.dismiss) private var dismiss

    init(current: SearchFilter, onApply: @escaping (SearchFilter) -> Void) {
        self.current = current
        self.onApply = onApply
        _draft = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort by") {
                    Picker("Sort", selection: $draft.sortOrder) {
                        ForEach(SearchFilter.SortOrder.allCases, id: \.self) { order in
                            Text(LocalizedStringKey(order.label)).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Upload date") {
                    Picker("Upload date", selection: $draft.uploadDate) {
                        ForEach(SearchFilter.UploadDate.allCases, id: \.self) { date in
                            Text(LocalizedStringKey(date.label)).tag(date)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section(String(localized: "search.filter.type", bundle: .module)) {
                    Picker(String(localized: "search.filter.type", bundle: .module), selection: $draft.type) {
                        ForEach(SearchFilter.VideoType.allCases, id: \.self) { type in
                            Text(LocalizedStringKey(type.label)).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Duration") {
                    Picker("Duration", selection: $draft.duration) {
                        ForEach(SearchFilter.Duration.allCases, id: \.self) { dur in
                            Text(LocalizedStringKey(dur.label)).tag(dur)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                #if !os(iOS)
                Section {
                    Button("Reset") { draft = .default }
                        .disabled(draft.isDefault)
                }
                #endif
            }
            .navigationTitle("Search filters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(draft)
                        dismiss()
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset") { draft = .default }
                        .disabled(draft.isDefault)
                }
                #endif
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier(AccessibilityID.searchFilterSheet)
    }
}
