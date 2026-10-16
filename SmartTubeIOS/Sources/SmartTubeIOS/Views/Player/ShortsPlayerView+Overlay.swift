import SmartTubeIOSCore
import SwiftUI

extension ShortsPlayerView {

    // MARK: - Always-visible index badge
    //
    // Rendered outside the ZStack (as an .overlay on the body) so UIViewRepresentable
    // elements inside the ZStack cannot absorb it from the accessibility tree.

    var indexBadge: some View {
        Text("\(currentIndex + 1) / \(videos.count)")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.4))
            .clipShape(Capsule())
            .accessibilityIdentifier(AccessibilityID.shortsIndexLabel)
            .padding(.top, 12)
            .padding(.trailing, 20)
    }

    // MARK: - Overlay

    var shortsOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: AppSymbol.chevronLeft)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .accessibilityIdentifier(AccessibilityID.shortsBackButton)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()
        }
    }

    #if os(iOS)
    var shortsSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 50, coordinateSpace: .global)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { value in
                guard !isTransitioning else { return }
                let dy = value.translation.height
                guard abs(dy) > abs(value.translation.width) else { return }
                let canMove = dy < 0 ? currentIndex + 1 < videos.count : currentIndex > 0
                slideOffset = canMove ? dy : dy * 0.15
            }
            .onEnded { value in
                guard !isTransitioning else { return }
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
