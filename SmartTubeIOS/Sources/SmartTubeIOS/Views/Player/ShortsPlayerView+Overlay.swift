import SmartTubeIOSCore
import SwiftUI

extension ShortsPlayerView {

    var shortsOverlay: some View {
        VStack {
            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: AppSymbol.chevronLeft)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Back")
                .accessibilityIdentifier(AccessibilityID.shortsBackButton)
                Spacer()
                Text("\(currentIndex + 1) / \(videos.count)")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier(AccessibilityID.shortsIndexLabel)
                Button {
                    isMuted.toggle()
                    vm.player.isMuted = isMuted
                } label: {
                    Image(systemName: isMuted ? AppSymbol.muted : AppSymbol.speaker)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                .accessibilityValue(isMuted ? "Muted" : "Sound on")
                .accessibilityIdentifier(AccessibilityID.shortsMuteButton)
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? AppSymbol.pause : AppSymbol.play)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(vm.isLoading || vm.error != nil)
                .accessibilityLabel(vm.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier(AccessibilityID.shortsPlayPauseButton)
            }
            .font(.title2)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .padding()
            .background(.black.opacity(0.5))

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text(vm.currentVideo?.title ?? "")
                    .font(.headline)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.shortsTitleLabel)
                Text(vm.currentVideo?.channelTitle ?? "")
                    .font(.subheadline)
                    .lineLimit(1)
                #if !os(tvOS)
                Slider(
                    value: Binding(
                        get: { vm.isScrubbing ? vm.scrubTime : vm.currentTime },
                        set: { position in
                            if vm.isScrubbing {
                                vm.updateScrub(to: position)
                            } else {
                                // Accessibility adjustments do not send editing callbacks.
                                vm.seek(to: position)
                            }
                        }),
                    in: 0...max(vm.duration, 1),
                    onEditingChanged: { editing in
                        if editing { vm.beginScrubbing() } else { vm.commitScrub() }
                    }
                )
                .tint(.white)
                .disabled(vm.duration <= 0 || vm.isLoading || vm.error != nil)
                .accessibilityLabel("Playback position")
                .accessibilityValue(formatDuration(vm.isScrubbing ? vm.scrubTime : vm.currentTime))
                .accessibilityIdentifier(AccessibilityID.shortsSeekBar)
                #endif
                Text("\(formatDuration(vm.currentTime)) / \(formatDuration(vm.duration))")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier(AccessibilityID.shortsTimeLabel)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.5))
        }
        .foregroundStyle(.white)
    }

    #if os(iOS)
    var shortsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !isTransitioning, !vm.isScrubbing else { return }
                let dy = value.translation.height
                guard abs(dy) > abs(value.translation.width) else { return }
                let canMove = dy < 0 ? currentIndex + 1 < videos.count : currentIndex > 0
                slideOffset = canMove ? dy : dy * 0.15
            }
            .onEnded { value in
                guard !isTransitioning, !vm.isScrubbing else { return }
                let dy = value.translation.height
                if let target = ShortsNavigation.targetIndex(
                    vertical: dy, horizontal: abs(value.translation.width),
                    current: currentIndex, count: videos.count
                ) {
                    performVerticalTransition(direction: dy < 0 ? -1 : 1) { goTo(target) }
                } else if dy > abs(value.translation.width), currentIndex == 0 {
                    loadMoreAtStart()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { slideOffset = 0 }
                }
            }
    }
    #endif
}
