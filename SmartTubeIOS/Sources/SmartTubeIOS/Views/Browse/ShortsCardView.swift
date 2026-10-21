import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsCardView
//
// VF/ShortsCard, shelf variant: a 9:16 cover with the duration, then title (two lines) and channel.
// Callers set the width; the height follows the cover and the text. One accessibility element that opens the Short
// and carries the card menu (VideoCardMenu.swift, the same as every video card) as actions; the menu also opens from
// the context menu, from a More button next to the title (on hover on the Mac) and, on tvOS, where the card is a
// button, from Play/Pause. Used inside ShortsRowSection.

struct ShortsCardView: View {
    let video: Video
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var menu = VideoCardMenuState()
    #if os(macOS)
    @State private var isHovering = false
    #endif

    /// Primary thumbnail URL: portrait oardefault.jpg when the API provided one
    /// (reelItemRenderer), landscape thumbnailURL otherwise.
    /// YouTube returns HTTP 200 with a blank black image for oardefault.jpg when
    /// no portrait thumbnail exists, so we skip it for non-reelItemRenderer Shorts.
    private var primaryURL: URL? {
        video.hasPortraitThumbnail ? video.portraitThumbnailURL : video.thumbnailURL
    }

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    /// Space the text leaves for the More button.
    private var moreButtonInset: CGFloat {
        #if os(tvOS)
        return 0
        #else
        return VideoCardMoreButton.inset
        #endif
    }

    var body: some View {
        #if os(tvOS)
        // The button is the one focusable, accessible element: Select opens, long press shows the menu.
        Button(action: onTap) { card }
            .buttonStyle(.plain)
            .accessibilityLabel(spokenSummary)
            .accessibilityActions { menuItems(nested: false) }
            .contextMenu { menuItems() }
            .videoCardMenu(video: video, playlistId: video.playlistId, title: video.title, state: menu)
        #else
        let summary =
            card
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onTap)
            .accessibilityActions { menuItems(nested: false) }
            .contextMenu { menuItems() }
            .overlay(alignment: Alignment(horizontal: .trailing, vertical: .cardTextTop)) {
                VideoCardMoreButton(
                    video: video, playlistId: video.playlistId, title: video.title, visible: moreButtonVisible,
                    state: menu)
            }
            .videoCardMenu(video: video, playlistId: video.playlistId, title: video.title, state: menu)
        #if os(macOS)
        summary.onHover { isHovering = $0 }
        #else
        // A container for the summary and the More button.
        summary.accessibilityElement(children: .contain)
        #endif
        #endif
    }

    #if !os(tvOS)
    private var moreButtonVisible: Bool {
        #if os(macOS)
        return isHovering
        #else
        return true
        #endif
    }
    #endif

    private var spokenSummary: Text {
        Text(
            [video.title, video.channelTitle, video.accessibilityDuration ?? ""].filter { !$0.isEmpty }
                .joined(separator: ", "))
    }

    private func menuItems(nested: Bool = true) -> some View {
        VideoCardMenuItems(video: video, playlistId: video.playlistId, nested: nested, state: menu)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: VFSpace.s8) {
            Color.clear
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay(ThumbnailFillView(primaryURL: primaryURL, fallbackURLs: video.thumbnailFallbackURLs))
                .clipShape(RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    let duration = video.formattedDuration
                    if !duration.isEmpty {
                        MediaBadge { Text(duration) }
                    }
                }
            VStack(alignment: .leading, spacing: VFSpace.s4 / 2) {
                // Two reserved lines keep a row even; at accessibility sizes the text wraps in full instead.
                let title = Text(video.title).font(.footnote.weight(.semibold))
                if isLargeText {
                    title.fixedSize(horizontal: false, vertical: true)
                } else {
                    title.lineLimit(2, reservesSpace: true)
                }
                if !video.channelTitle.isEmpty {
                    Text(video.channelTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isLargeText ? nil : 1)
                }
                // The duration badge stops growing at xxxLarge, so accessibility sizes repeat it as text.
                if isLargeText, !video.formattedDuration.isEmpty {
                    Text(video.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, moreButtonInset)
            .alignmentGuide(.cardTextTop) { $0[.top] }
        }
    }
}
