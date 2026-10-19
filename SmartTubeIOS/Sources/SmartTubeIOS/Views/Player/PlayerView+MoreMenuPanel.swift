import SmartTubeIOSCore
import SwiftUI

enum PlayerMoreMenuDestination {
    case offline(Video), captions, audioTrack, description, comments
    #if os(iOS)
    case share(URL)
    #endif
}

extension PlayerView {
    /// A second presentation must wait until the native More sheet/popover has dismissed.
    func openMoreMenuDestination(_ destination: PlayerMoreMenuDestination) {
        #if os(iOS)
        moreMenuDestination = destination
        showMoreMenu = false
        #else
        showMoreMenu = false
        presentMoreMenuDestination(destination)
        #endif
    }

    private func presentMoreMenuDestination(_ destination: PlayerMoreMenuDestination) {
        switch destination {
        case .offline(let video): offlineDownloadVideo = video
        case .captions: showCaptionPicker = true
        case .audioTrack: showAudioTrackPicker = true
        case .description: showDescriptionSheet = true
        case .comments:
            showCommentsSheet = true
            loadComments()
        #if os(iOS)
        case .share(let url): presentShareSheet(url: url)
        #endif
        }
    }

    #if os(iOS)
    func moreMenuDidDismiss() {
        guard !showMoreMenu, let destination = moreMenuDestination else { return }
        moreMenuDestination = nil
        presentMoreMenuDestination(destination)
    }

    var moreMenuPanel: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        return PlayerOptionPanel(
            title: Text("More", bundle: .module), isPresented: $showMoreMenu,
            cancelAccessibilityIdentifier: AccessibilityID.playerMoreMenuCancelButton
        ) {
            ScrollView {
                VStack(spacing: VFSpace.s12) {
                    VStack(spacing: VFSpace.s4) {
                        OfflineSavedTitle(title: currentVideo.title, videoID: currentVideo.id, spacing: VFSpace.s8)
                            .font(.headline)
                        if !currentVideo.channelTitle.isEmpty {
                            Text(currentVideo.channelTitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, VFSpace.s8)

                    moreMenuGroup { moreMenuChannelRow }
                    moreMenuGroup {
                        moreMenuLikeDislikeRow
                        moreMenuShareRow
                        moreMenuDownloadRow
                        moreMenuQueueShuffleRow
                    }
                    moreMenuGroup {
                        moreMenuCaptionsRow
                        moreMenuAudioTrackRow
                    }
                    moreMenuGroup {
                        moreMenuDescriptionRow
                        moreMenuCommentsRow
                        moreMenuStatsForNerdsRow
                    }
                }
                .font(.body)
                .labelStyle(PlayerMoreMenuLabelStyle())
                .padding(VFSpace.s16)
            }
            .accessibilityIdentifier(AccessibilityID.playerMoreMenuScrollView)
            .background(VFColor.surface)
        }
        .accessibilityIdentifier(AccessibilityID.playerMoreMenu)
    }

    private func moreMenuGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Group(subviews: content()) { rows in
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    row
                }
            }
            .background(VFColor.elevated, in: RoundedRectangle(cornerRadius: VFRadius.card))
        }
    }
    #endif
}

#if os(iOS)
/// The same touch targets and semantic labels as option rows, with grouped action icons (P-Player-More).
private struct PlayerMoreMenuLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: VFSpace.s12) {
            configuration.icon
                .foregroundStyle(.tint)
                .frame(width: VFTarget.pointer, height: VFTarget.pointer)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: VFRadius.small))
                .accessibilityHidden(true)
            configuration.title
                .foregroundStyle(.primary)
        }
        .frame(minHeight: VFTarget.touch)
    }
}
#endif
