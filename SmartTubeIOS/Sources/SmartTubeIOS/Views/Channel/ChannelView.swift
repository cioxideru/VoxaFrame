import SmartTubeIOSCore
import SwiftUI

// MARK: - ChannelView
//
// Displays channel info, subscriber count and a grid of recent uploads.
// Mirrors the Android `ChannelFragment`.

// MARK: - ChannelFilter

private enum ChannelFilter: String, CaseIterable {
    case all = "All"
    case shorts = "Shorts"
}

public struct ChannelView: View {
    public let channelId: String
    @State private var vm: ChannelViewModel
    @State private var selectedVideo: Video?
    @State private var shortsPresentation: ShortsPresentation?
    @State private var channelDestination: ChannelDestination?
    @State private var filter: ChannelFilter = .all
    @State private var confirmUnsubscribe = false
    @Environment(SettingsStore.self) private var store
    @Environment(AuthService.self) private var auth
    private let api: InnerTubeAPI
    @Environment(\.isLandscapeLayout) private var isLandscapeLayout
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif

    public init(channelId: String, api: InnerTubeAPI) {
        self.channelId = channelId
        self.api = api
        _vm = State(initialValue: ChannelViewModel(api: api))
    }

    public var body: some View {
        Group {
            if vm.isLoading && vm.channel == nil {
                ProgressView("Loading channel…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("channel.view")
            } else {
                content
            }
        }
        .navigationTitle(vm.channel?.title ?? "Channel")
        .task(id: auth.accessToken) {
            await api.setAuthToken(auth.accessToken)
            vm.load(channelId: channelId, signedIn: auth.isSignedIn)
        }
        #if !os(iOS) && !os(macOS)
        .fullScreenCover(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        #if os(macOS)
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
        #if !os(macOS)
        .fullScreenCover(item: $shortsPresentation) { target in
            ShortsPlayerView(videos: target.videos, startIndex: target.startIndex, api: api)
        }
        #endif
        .alert(
            "Error",
            isPresented: Binding(get: { vm.error != nil }, set: { if !$0 { vm.error = nil } }),
            presenting: vm.error
        ) { _ in
            Button("Retry") { vm.load(channelId: channelId, signedIn: auth.isSignedIn) }
            Button("Dismiss", role: .cancel) { vm.error = nil }
        } message: { err in
            Text(err.localizedDescription)
        }
        .confirmationDialog("Unsubscribe?", isPresented: $confirmUnsubscribe, titleVisibility: .visible) {
            Button("Unsubscribe", role: .destructive) { Task { await vm.setSubscribed(false) } }
                .accessibilityIdentifier(AccessibilityID.subscriptionConfirm)
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier(AccessibilityID.subscriptionCancel)
        } message: {
            let title = vm.channel?.title ?? ""
            if auth.isSignedIn {
                Text("\(title) will leave Subscriptions in your Google account.", bundle: .module)
            } else {
                Text("\(title) will be removed from the subscriptions on this device.", bundle: .module)
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Channel header
                if let channel = vm.channel {
                    channelHeader(channel)
                }

                // All / Shorts filter
                Picker("Filter", selection: $filter) {
                    ForEach(ChannelFilter.allCases, id: \.self) { tab in
                        Text(LocalizedStringKey(tab.rawValue), bundle: .module).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)
                .accessibilityIdentifier("channel.filterPicker")

                let filtered = filteredVideos
                if filter == .shorts {
                    shortsGrid(filtered)
                } else {
                    videosGrid(filtered)
                }

                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                }
            }
        }
        .refreshable { await vm.refresh(channelId: channelId, signedIn: auth.isSignedIn) }
        .accessibilityIdentifier("channel.view")
    }

    // MARK: - Filtered data

    private var filteredVideos: [Video] {
        switch filter {
        case .all: return vm.videos.filter { !store.settings.hideShorts || !$0.isShort }
        case .shorts: return vm.videos.filter { $0.isShort }
        }
    }

    // MARK: - Grid layouts

    private func videosGrid(_ videos: [Video]) -> some View {
        let compact = store.settings.compactThumbnails
        return Group {
            if compact {
                LazyVStack(spacing: 0) {
                    ForEach(videos) { video in
                        VideoCardView(video: video, compact: true)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("video.card.\(video.id)")
                            .onTapGesture {
                                #if os(iOS)
                                playerRouter.open(video: video, api: api)
                                #else
                                selectedVideo = video
                                #endif
                            }
                            .onAppear {
                                if video.id == vm.videos.last?.id { vm.loadMore() }
                            }
                        Divider().padding(.horizontal)
                    }
                }
            } else {
                #if os(tvOS)
                let columnCount = 4
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(stride(from: 0, to: videos.count, by: columnCount)), id: \.self) { startIdx in
                        let rowVideos = Array(videos[startIdx..<min(startIdx + columnCount, videos.count)])
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(rowVideos) { video in
                                VideoCardView(video: video, compact: false, onSelect: { selectedVideo = video })
                                    .frame(maxWidth: .infinity)
                                    .accessibilityIdentifier("video.card.\(video.id)")
                            }
                            let remainder = columnCount - rowVideos.count
                            if remainder > 0 {
                                ForEach(0..<remainder, id: \.self) { _ in
                                    Color.clear.frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .onAppear {
                            if rowVideos.last?.id == vm.videos.last?.id { vm.loadMore() }
                        }
                    }
                }
                .padding()
                #else
                LazyVGrid(
                    columns: videoGridColumns(store.settings, landscape: isLandscapeLayout),
                    spacing: videoGridRowSpacing
                ) {
                    ForEach(videos) { video in
                        VideoCardView(video: video, compact: false)
                            .accessibilityIdentifier("video.card.\(video.id)")
                            .onTapGesture {
                                #if os(iOS)
                                playerRouter.open(video: video, api: api)
                                #else
                                selectedVideo = video
                                #endif
                            }
                            .onAppear {
                                if video.id == vm.videos.last?.id { vm.loadMore() }
                            }
                    }
                }
                .id(isLandscapeLayout)  // reset on column-count change — see VideoGridSection (#82)
                .padding()
                #endif
            }
        }
    }

    private func shortsGrid(_ videos: [Video]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(videos) { video in
                VideoCardView(video: video)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .onTapGesture { selectShort(video, from: videos) }
                    .onAppear {
                        if video.id == vm.videos.last?.id { vm.loadMore() }
                    }
            }
        }
        .padding(.horizontal)
        .accessibilityIdentifier("channel.videoGrid")
    }

    private func selectShort(_ video: Video, from videos: [Video]) {
        let idx = videos.firstIndex(where: { $0.id == video.id }) ?? 0
        shortsPresentation = ShortsPresentation(videos: videos, startIndex: idx)
    }

    private func channelHeader(_ channel: Channel) -> some View {
        VStack(spacing: VFSpace.s8) {
            AsyncImage(url: channel.thumbnailURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(VFColor.surface)
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .accessibilityHidden(true)

            Text(verbatim: channel.title)  // verbatim: channel name
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(AccessibilityID.channelTitle)
            if let subs = channel.subscriberCount {
                Text(verbatim: subs)  // verbatim: subscriber count from YouTube
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let desc = channel.description, !desc.isEmpty {
                Text(verbatim: desc)  // verbatim: channel description
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            subscriptionButton(channel)
                .padding(.top, VFSpace.s4)
            if let note = subscriptionNote(channel) {
                note
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(VFSpace.s16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.channelHeader)
    }

    /// Subscribe is the screen's primary action; once subscribed it steps back to a bordered Unsubscribe
    /// that asks first. Disabled until the current state is known and while a change is in flight.
    @ViewBuilder
    private func subscriptionButton(_ channel: Channel) -> some View {
        let label = HStack(spacing: VFSpace.s8) {
            if vm.isChangingSubscription {
                ProgressView().controlSize(.small)
            }
            Label {
                Text(channel.isSubscribed ? LocalizedStringKey("Unsubscribe") : "Subscribe", bundle: .module)
            } icon: {
                Image(systemName: channel.isSubscribed ? AppSymbol.personCircleMinus : AppSymbol.addCircle)
            }
        }
        Group {
            if channel.isSubscribed {
                Button {
                    confirmUnsubscribe = true
                } label: {
                    label
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await vm.setSubscribed(true) }
                } label: {
                    label
                }
                .buttonStyle(.vfProminent)
            }
        }
        .disabled(!vm.isSubscriptionLoaded || vm.isChangingSubscription || vm.isLoading)
        .accessibilityIdentifier(AccessibilityID.channelSubscriptionButton)
    }

    /// Where the subscription lives: a guest's stays on this device and is not moved to Google later.
    private func subscriptionNote(_ channel: Channel) -> Text? {
        switch (channel.isSubscribed, auth.isSignedIn) {
        case (true, true): Text("Subscribed with your Google account", bundle: .module)
        case (true, false): Text("Subscribed on this device", bundle: .module)
        case (false, false): Text("Without signing in, the subscription is saved on this device", bundle: .module)
        case (false, true): nil
        }
    }

}
