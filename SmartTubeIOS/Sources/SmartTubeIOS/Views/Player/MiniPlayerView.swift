#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit
import SmartTubeIOSCore

// MARK: - MiniPlayerView

/// Compact bar overlaid at the bottom of MainTabView when the player is minimized.
/// Shows a live video thumbnail (the shared PersistentPlayerHostView), title,
/// channel, play/pause button, and a close button.
/// Tapping the bar expands back to full-screen.
struct MiniPlayerView: View {
    @Environment(PlayerStateStore.self) private var playerState

    var body: some View {
        HStack(spacing: 8) {
            // Live video thumbnail (same AVPlayerLayer, transplanted here)
            PersistentPlayerLayerView(presentation: .miniPlayer, videoGravity: .resizeAspectFill)
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(playerState.playingVideo?.title ?? "")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("miniPlayer.titleLabel")
                Text(playerState.playingVideo?.channelTitle ?? "")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                playerState.vm.togglePlayPause()
            } label: {
                Image(systemName: playerState.vm.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier("miniPlayer.playPauseButton")

            Button {
                playerState.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityIdentifier("miniPlayer.closeButton")
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .frame(height: 62)
        .background(.regularMaterial)
        .contentShape(Rectangle())
        .onTapGesture { playerState.expand() }
        // Ensure child buttons remain individually discoverable by XCTest even though
        // the enclosing HStack carries its own onTapGesture (which can cause SwiftUI
        // to group all children into a single accessibility element).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.miniPlayerBar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

#endif
