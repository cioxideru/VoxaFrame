#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit
import SmartTubeIOSCore

// MARK: - MiniPlayerView

/// Compact bar overlaid at the bottom of MainTabView when the player is minimized.
/// Shows a live video thumbnail (the shared PersistentPlayerHostView), title,
/// channel, play/pause button, and a close button.
/// Expand, play/pause and close are separate controls with their own hit regions (VF/MiniPlayer);
/// the height follows Dynamic Type, and MainTabView reserves whatever height it measures.
/// At accessibility text sizes the texts move below the thumbnail and controls.
struct MiniPlayerView: View {
    @Environment(PlayerStateStore.self) private var playerState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // The thumbnail and texts stay separate, non-hit-testable elements (UI tests read the title);
        // taps on them, VoiceOver activation included, fall through to the expand button behind.
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: VFSpace.s8) {
                    HStack(spacing: VFSpace.s4) {
                        thumbnail.allowsHitTesting(false)
                        Spacer(minLength: 0)
                        controls
                    }
                    titles.allowsHitTesting(false)
                }
                .padding(.vertical, VFSpace.s8)
                .background { expandButton }
            } else {
                HStack(spacing: VFSpace.s4) {
                    HStack(spacing: VFSpace.s12) {
                        thumbnail
                        titles
                    }
                    .padding(.vertical, VFSpace.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .background { expandButton }
                    controls
                }
            }
        }
        .padding(.horizontal, VFSpace.s8)
        .vfGlass(in: RoundedRectangle(cornerRadius: VFRadius.panel, style: .continuous))
        // Ensure child buttons remain individually discoverable by XCTest.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.miniPlayerBar)
        .padding(.horizontal, horizontalSizeClass == .regular ? VFMargin.ipad : VFMargin.iphone)
        .padding(.bottom, VFSpace.s8)
    }

    /// Live video thumbnail (the shared AVPlayerLayer, transplanted here).
    private var thumbnail: some View {
        PersistentPlayerLayerView(presentation: .miniPlayer, videoGravity: .resizeAspectFill)
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: VFRadius.small, style: .continuous))
            .accessibilityHidden(true)
    }

    private var isSavedOffline: Bool {
        playerState.playingVideo.map { OfflineCoordinator.shared.savedIDs.ids.contains($0.id) } ?? false
    }

    /// Title and channel; at accessibility sizes the title gets a third line (the full title is in the expanded
    /// player's More → Description, and in the expand button's VoiceOver label).
    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playerState.playingVideo?.title ?? "")
                .font(.subheadline.weight(.semibold))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .foregroundStyle(.primary)
                .accessibilityIdentifier(AccessibilityID.miniPlayerTitle)
            HStack(spacing: VFSpace.s4) {
                if isSavedOffline { OfflineSavedMark() }
                Text(playerState.playingVideo?.channelTitle ?? "")
                    .font(.footnote)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var expandButton: some View {
        Button {
            playerState.expand()
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expandLabel)
    }

    /// "Expand player, <full title>, <channel>": VoiceOver hears the whole title even where the text is truncated.
    private var expandLabel: String {
        var label = String(localized: "Expand player", bundle: .module)
        for part in [playerState.playingVideo?.title, playerState.playingVideo?.channelTitle] {
            if let part, !part.isEmpty { label += ", \(part)" }
        }
        if isSavedOffline { label += ", " + String(localized: "Saved offline", bundle: .module) }
        return label
    }

    @ViewBuilder
    private var controls: some View {
        control(
            symbol: playerState.vm.isPlaying ? AppSymbol.pause : AppSymbol.play,
            label: playerState.vm.isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module),
            identifier: AccessibilityID.miniPlayerPlayPause
        ) {
            playerState.vm.togglePlayPause()
        }
        .foregroundStyle(.primary)

        control(
            symbol: AppSymbol.xmark, label: Text("Close", bundle: .module),
            identifier: AccessibilityID.miniPlayerClose
        ) {
            playerState.stop()
        }
        .foregroundStyle(.secondary)
    }

    private func control(
        symbol: String, label: Text, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(minWidth: VFTarget.touch, minHeight: VFTarget.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

#endif
