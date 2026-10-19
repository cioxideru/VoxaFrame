import SmartTubeIOSCore
import SwiftUI

extension PlayerView {
    // MARK: - Description panel

    /// Same container and header as the More menu; see `playerOptionPanel`.
    var descriptionPanel: some View {
        let panel = PlayerOptionPanel(
            title: Text("Description", bundle: .module), isPresented: $showDescriptionSheet,
            cancelAccessibilityIdentifier: AccessibilityID.playerDescriptionPanelCancel
        ) {
            ScrollView { descriptionContent }
                .background(VFColor.surface)
        }
        .accessibilityIdentifier(AccessibilityID.playerDescriptionPanel)
        #if os(tvOS)
        return
            panel
            .focusScope(descriptionOverlayNamespace)
            .onExitCommand { showDescriptionSheet = false }
        #else
        return panel
        #endif
    }

    /// Title and channel, then the linkified description, each in a grouped card; shared with the Mac inspector.
    var descriptionContent: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        let description = currentVideo.description ?? ""
        return VStack(alignment: .leading, spacing: VFSpace.s12) {
            VStack(alignment: .leading, spacing: VFSpace.s4) {
                Text(currentVideo.title)
                    .font(.headline)
                if !currentVideo.channelTitle.isEmpty {
                    Text(currentVideo.channelTitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .descriptionCard()
            Group {
                if !description.isEmpty {
                    Text(descriptionAttributedString(description))
                } else {
                    Text("No description available.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body)
            .descriptionCard()
        }
        .padding(VFSpace.s16)
        .frame(maxWidth: VFColumn.readableMaximum)
        .frame(maxWidth: .infinity)
    }

    func descriptionAttributedString(_ string: String) -> AttributedString {
        var attributed = AttributedString(string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return attributed
        }
        let nsString = string as NSString
        let matches = detector.matches(in: string, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            guard let range = Range(match.range, in: string),
                let url = match.url,
                let attrRange = Range(range, in: attributed)
            else { continue }
            attributed[attrRange].link = url
        }
        // Timestamp linkification: add smarttube://seek/<seconds> links for MM:SS / HH:MM:SS spans.
        // Only applied where NSDataDetector has not already set a link (URLs take precedence).
        for (range, seconds) in findTimestamps(in: string) {
            guard let attrRange = Range(range, in: attributed) else { continue }
            if attributed[attrRange].link == nil {
                attributed[attrRange].link = URL(string: "smarttube://seek/\(Int(seconds))")
            }
        }
        return attributed
    }

    // MARK: - Comments panel

    var commentsPanel: some View {
        let panel = CommentsPanel(
            comments: vm.comments.comments, isLoading: vm.comments.isLoading, isPresented: $showCommentsSheet)
        #if os(tvOS)
        return
            panel
            .focusScope(commentsOverlayNamespace)
            .onExitCommand { showCommentsSheet = false }
        #else
        return panel
        #endif
    }

    // MARK: - Comments loading

    func loadComments() {
        let videoId = (vm.playerInfo?.video ?? video).id
        vm.comments.load(videoId: videoId)
    }

}

extension View {
    /// A rounded grouped card, like the More menu's groups.
    fileprivate func descriptionCard() -> some View {
        padding(VFSpace.s16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VFColor.elevated, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
    }
}
