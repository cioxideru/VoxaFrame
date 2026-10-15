#if !os(tvOS)
import SmartTubeIOSCore
import SwiftUI

extension TOSPlayerView {
    // MARK: - Comments overlay
    //
    // Transferred from PlayerView+Overlays.commentsOverlay — same dim-backdrop +
    // bottom-sheet layout and the same shared CommentRowView. tvOS-only bits
    // (focusScope/.onExitCommand) are dropped: TOSPlayerView is `!os(tvOS)`.
    func commentsOverlay(vm: TOSPlayerViewModel) -> some View {
        CommentsOverlayView(
            comments: vm.comments.comments,
            isLoading: vm.comments.isLoading,
            onDismiss: { showCommentsSheet = false },
            accessibilityId: "tosPlayer.commentsOverlay"
        )
    }

    // MARK: - Chapters overlay
    //
    // #10 (closes #68, #105): the TOS player embeds YouTube's own IFrame page
    // directly rather than the IFrame JS API, so SmartTube has no control over —
    // and can't add markers to — the embed's own scrub bar. This overlay is the
    // native equivalent: a tap-to-jump list, seeking via vm.seekTo (a plain
    // `video.currentTime = X` JS assignment, not a user-activation-gated API).
    func chaptersOverlay(vm: TOSPlayerViewModel) -> some View {
        ChaptersOverlayView(
            chapters: vm.chapters,
            onSelect: { chapter in
                vm.seekTo(chapter.startTime)
                showChaptersSheet = false
            },
            onDismiss: { showChaptersSheet = false },
            accessibilityId: "tosPlayer.chaptersOverlay"
        )
    }

    // MARK: - SponsorBlock toast

    func sponsorToast(for segment: SponsorSegment, vm: TOSPlayerViewModel) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Spacer()
                reportSegmentButton(segment, vm: vm)
                Button {
                    vm.seekTo(segment.end)
                    vm.currentToastSegment = nil
                } label: {
                    Label(skipLabel(for: segment.category), systemImage: AppSymbol.skipForward)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 60)
        }
        .accessibilityIdentifier(AccessibilityID.tosPlayerSkipToast)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: vm.currentToastSegment?.start)
    }

    /// #20: shown briefly after an auto-skip (as opposed to `sponsorToast`, which is
    /// the manual tap-to-skip prompt for showToast-configured categories). Tapping
    /// seeks back into the segment via `vm.undoAutoSkip()`.
    func undoAutoSkipToast(for segment: SponsorSegment, vm: TOSPlayerViewModel) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Spacer()
                reportSegmentButton(segment, vm: vm)
                Button {
                    vm.undoAutoSkip()
                } label: {
                    Label("\(skippedLabel(for: segment.category)) — Undo", systemImage: AppSymbol.undo)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 60)
        }
        .accessibilityIdentifier(AccessibilityID.tosPlayerUndoAutoSkipToast)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: vm.recentAutoSkip?.start)
    }

    /// Small "flag" icon button shared by both SponsorBlock toasts (#67).
    private func reportSegmentButton(_ segment: SponsorSegment, vm: TOSPlayerViewModel) -> some View {
        Button {
            reportSegment(segment, vm: vm)
        } label: {
            Image(systemName: AppSymbol.reportFlag)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(8)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Report Incorrect Segment", bundle: .module))
        .accessibilityIdentifier(AccessibilityID.tosPlayerReportSegmentButton)
    }

    /// #67: submits a downvote to SponsorBlock for this segment and shows a brief
    /// confirmation. Wired from both sponsorToast and undoAutoSkipToast's report button.
    private func reportSegment(_ segment: SponsorSegment, vm: TOSPlayerViewModel) {
        Task {
            let ok = await vm.reportIncorrectSegment(segment)
            reportSegmentAlert = DownloadAlertItem(
                title: ok
                    ? String(localized: "Reported", bundle: .module)
                    : String(localized: "Could Not Report", bundle: .module),
                message: ok
                    ? String(
                        localized: "Thanks for the feedback — this segment has been reported to SponsorBlock.",
                        bundle: .module)
                    : String(localized: "The report couldn't be sent. Please try again later.", bundle: .module)
            )
        }
    }

    private func skippedLabel(for category: SponsorSegment.Category) -> String {
        switch category {
        case .sponsor: return "Skipped Sponsor"
        case .selfPromo: return "Skipped Self-Promo"
        case .interaction: return "Skipped Interaction"
        case .intro: return "Skipped Intro"
        case .outro: return "Skipped Outro"
        case .preview: return "Skipped Preview"
        case .filler: return "Skipped Filler"
        case .musicOfftopic: return "Skipped Music"
        case .poiHighlight: return "Skipped to Highlight"
        }
    }

    private func skipLabel(for category: SponsorSegment.Category) -> String {
        switch category {
        case .sponsor: return "Skip Sponsor"
        case .selfPromo: return "Skip Self-Promo"
        case .interaction: return "Skip Interaction"
        case .intro: return "Skip Intro"
        case .outro: return "Skip Outro"
        case .preview: return "Skip Preview"
        case .filler: return "Skip Filler"
        case .musicOfftopic: return "Skip Music"
        case .poiHighlight: return "Skip to Highlight"
        }
    }
}
#endif
