import SwiftUI

// MARK: - HomeLoadingView
//
// First load of a Home section: a status line and skeleton cards in the grid's columns, so the layout does not jump
// when the feed arrives. The skeletons are decorative and hidden from VoiceOver; the status line is read.

struct HomeLoadingView: View {
    let columns: Int

    private static let skeletonRows = 2

    var body: some View {
        VStack(alignment: .leading, spacing: VFSpace.s16) {
            Label {
                Text("Loading your feed…", bundle: .module)
            } icon: {
                ProgressView()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            ForEach(0..<Self.skeletonRows, id: \.self) { _ in
                HStack(alignment: .top, spacing: videoGridRowSpacing) {
                    ForEach(0..<max(columns, 1), id: \.self) { _ in skeletonCard }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, videoGridMargin)
        .padding(.top, VFSpace.s12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Cover and two text lines; the lines are redacted text, so they follow Dynamic Type.
    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: VFSpace.s8) {
            RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                .fill(VFColor.surface)
                .aspectRatio(16 / 9, contentMode: .fit)
            Text(verbatim: String(repeating: "x", count: 28))  // verbatim: redacted placeholder, never shown
                .font(.subheadline)
                .lineLimit(1)
            Text(verbatim: String(repeating: "x", count: 16))  // verbatim: redacted placeholder, never shown
                .font(.footnote)
                .lineLimit(1)
        }
        .redacted(reason: .placeholder)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - HomeErrorBanner
//
// VF/Banner, error tone: a refresh or next page failed while earlier videos are still shown. It stays until the retry
// succeeds and never covers the list.

struct HomeErrorBanner: View {
    let retry: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the button goes under the message instead of squeezing it.
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VFSpace.s12))
            : AnyLayout(HStackLayout(spacing: VFSpace.s12))
        layout {
            HStack(alignment: .firstTextBaseline, spacing: VFSpace.s8) {
                Image(systemName: AppSymbol.warning)
                    .foregroundStyle(VFColor.warning)
                    .accessibilityHidden(true)
                Text("Couldn't refresh. Showing the videos loaded earlier.", bundle: .module)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: retry) {
                Text("Try Again", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
        .padding(VFSpace.s12)
        .background(VFColor.surface, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous)
                .strokeBorder(VFColor.border, lineWidth: 1)
        }
        .padding(.horizontal, videoGridMargin)
        .padding(.vertical, VFSpace.s8)
    }
}

// MARK: - ShortsShelfHeader

/// Above a Shorts row in the mixed feeds; a heading for VoiceOver navigation.
struct ShortsShelfHeader: View {
    var body: some View {
        Text("Shorts", bundle: .module)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, videoGridMargin)
            .padding(.top, VFSpace.s12)
    }
}

// MARK: - Feed block group

extension View {
    /// Groups a feed block's cards under `id`. Always the same modifiers: switching them when the last block
    /// grows past one card would give the block a new identity and redraw every card in it.
    func feedBlockGroup(_ id: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
}
