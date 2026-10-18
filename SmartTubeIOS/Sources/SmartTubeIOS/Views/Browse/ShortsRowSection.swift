import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsRowSection

/// Portrait (9:16) card row/grid section.
///
/// Use `scrollAxis = .horizontal` (default) for the horizontal scrolling shelf
/// shown in all non-Shorts feed chips (Home shelf, Subscriptions, Recommended, etc.).
/// Use `scrollAxis = .vertical` for the Shorts chip so users can scroll down
/// through all Shorts naturally.
struct ShortsRowSection: View {
    let videos: [Video]
    let onSelect: (Video) -> Void
    var accessibilityID: String = ""
    /// Called when the last card becomes visible — triggers the next page load.
    var loadMore: (() -> Void)? = nil
    /// Scroll direction. Defaults to `.horizontal` (standard portrait shelf).
    /// Pass `.vertical` for the Shorts chip to enable natural downward scrolling.
    var scrollAxis: Axis.Set = .horizontal

    // MARK: - Constants

    #if os(tvOS)
    private let cardWidth: CGFloat = 200
    #else
    /// Card width on iOS/iPadOS: ~120 pt gives roughly 3 cards on an iPhone screen.
    private let cardWidth: CGFloat = 120
    /// The shelf card grows with Dynamic Type, up to twice its width, so large titles still wrap into words.
    @ScaledMetric(relativeTo: .footnote) private var scaledCardWidth: CGFloat = 120
    private var shelfCardWidth: CGFloat { min(scaledCardWidth, cardWidth * 2) }
    #endif

    private static let verticalTVLimit = 9

    // MARK: - Body

    var body: some View {
        if scrollAxis == .vertical {
            verticalBody
        } else {
            horizontalBody
        }
    }

    // MARK: - Horizontal layout (all chips except Shorts)

    @ViewBuilder private var horizontalBody: some View {
        #if os(tvOS)
        // On tvOS, ScrollView(.horizontal) consumes UP/DOWN directional events
        // from the Siri remote, trapping focus inside the row and preventing
        // navigation to the content below. Fit the ten cards into a plain HStack instead.
        HStack(alignment: .top, spacing: videoGridRowSpacing) {
            ForEach(Array(videos.prefix(HomeFeedLayout.shortsPerRow))) { video in
                Button {
                    onSelect(video)
                } label: {
                    ShortsCardView(video: video, onTap: { onSelect(video) })
                        .containerRelativeFrame(.horizontal) { width, _ in
                            min(
                                cardWidth,
                                max(
                                    1,
                                    (width - 32 - videoGridRowSpacing
                                        * CGFloat(HomeFeedLayout.shortsPerRow - 1))
                                        / CGFloat(HomeFeedLayout.shortsPerRow)))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.shortsCard(video.id))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .accessibilityIdentifier(accessibilityID)
        .focusSection()
        #else
        let scrollView = ScrollView(.horizontal, showsIndicators: true) {
            // Eager HStack (not LazyHStack): the endless-scroll cascade pre-loads
            // dozens of cards into `videos` in the background,
            // and a LazyHStack would only materialize the few cards near the
            // visible viewport, leaving the rest invisible (and untestable via
            // accessibility) until the user manually scrolls past them.
            HStack(alignment: .top, spacing: videoGridRowSpacing) {
                ForEach(videos) { video in
                    ShortsCardView(video: video, onTap: { onSelect(video) })
                        .frame(width: shelfCardWidth)
                        .accessibilityIdentifier(AccessibilityID.shortsCard(video.id))
                }
            }
            .padding(.horizontal, videoGridMargin)
            .padding(.top, 4)
            // Bottom padding gives the scroll indicator room to render without
            // being clipped by fixedSize(vertical: true) below.
            .padding(.bottom, 12)
        }
        // Prevent the horizontal ScrollView from expanding to fill the full
        // height offered by a VStack parent (e.g. when pinned above a ScrollView).
        // fixedSize(vertical: true) makes it hug its content height instead.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue("\(videos.count)")

        // Fire loadMore? based on scroll position (distance from the trailing edge
        // of content to the trailing edge of the visible viewport) instead of
        // per-item .onAppear — the eager HStack above materializes every item's
        // .onAppear at creation/array-growth time regardless of viewport
        // visibility, so an .onAppear-based trigger only fires once during the
        // initial preload cascade and never again on user scroll.
        if #available(iOS 18, macOS 15, tvOS 18, *) {
            scrollView.onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceToEnd = geometry.contentSize.width - geometry.visibleRect.maxX
                return distanceToEnd <= cardWidth * 2
            } action: { _, isNearEnd in
                if isNearEnd { loadMore?() }
            }
        } else {
            scrollView
        }
        #endif
    }

    // MARK: - Vertical layout (Shorts chip)

    @ViewBuilder private var verticalBody: some View {
        #if os(tvOS)
        // tvOS: plain LazyVStack capped at verticalTVLimit — no ScrollView
        // to avoid trapping Siri remote directional events.
        LazyVStack(alignment: .leading, spacing: videoGridRowSpacing) {
            ForEach(Array(videos.prefix(Self.verticalTVLimit))) { video in
                Button {
                    onSelect(video)
                } label: {
                    ShortsCardView(video: video, onTap: { onSelect(video) })
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.shortsCard(video.id))
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .accessibilityIdentifier(accessibilityID)
        .focusSection()
        #else
        let scrollView = ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: videoGridRowSpacing) {
                ForEach(videos) { video in
                    ShortsCardView(video: video, onTap: { onSelect(video) })
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(AccessibilityID.shortsCard(video.id))
                }
            }
            .padding(.horizontal, videoGridMargin)
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue("\(videos.count)")

        // Fire loadMore? based on scroll position (distance from the bottom edge
        // of content to the bottom edge of the visible viewport) — see horizontalBody
        // for why an .onAppear-based trigger doesn't work here.
        if #available(iOS 18, macOS 15, tvOS 18, *) {
            scrollView.onScrollGeometryChange(for: Bool.self) { geometry in
                let distanceToEnd = geometry.contentSize.height - geometry.visibleRect.maxY
                return distanceToEnd <= cardWidth * 8
            } action: { _, isNearEnd in
                if isNearEnd { loadMore?() }
            }
        } else {
            scrollView
        }
        #endif
    }
}
