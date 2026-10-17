import SmartTubeIOSCore
import SwiftUI

extension PlayerView {
    // MARK: - Description overlay

    var descriptionOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { showDescriptionSheet = false }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        showDescriptionSheet = false
                    } label: {
                        Image(systemName: AppSymbol.xmark)
                            .font(.system(size: 16, weight: .semibold))
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("Description")
                        .fontWeight(.semibold)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 4)
                Divider()
                ScrollView { descriptionContent }
                    .frame(maxHeight: 400)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            #if os(tvOS)
            .focusScope(descriptionOverlayNamespace)
            .onExitCommand { showDescriptionSheet = false }
            #endif
            .padding(.horizontal, 8)
            .safeAreaPadding(.horizontal)
            .padding(.bottom, 8)
        }
        .ignoresSafeArea()
    }

    /// Title, channel and linkified description of the current video; shared with the Mac inspector.
    var descriptionContent: some View {
        let currentVideo = vm.playerInfo?.video ?? video
        let description = currentVideo.description ?? ""
        return VStack(alignment: .leading, spacing: 12) {
            Text(currentVideo.title)
                .font(.headline)
            if !currentVideo.channelTitle.isEmpty {
                Text(currentVideo.channelTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !description.isEmpty {
                Text(descriptionAttributedString(description))
                    .font(.body)
            } else {
                Text("No description available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
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

    // MARK: - Comments overlay

    var commentsOverlay: some View {
        #if os(tvOS)
        CommentsOverlayView(
            comments: vm.comments.comments,
            isLoading: vm.comments.isLoading,
            onDismiss: { showCommentsSheet = false },
            focusNamespace: commentsOverlayNamespace
        )
        #else
        CommentsOverlayView(
            comments: vm.comments.comments,
            isLoading: vm.comments.isLoading,
            onDismiss: { showCommentsSheet = false }
        )
        #endif
    }

    // MARK: - Comments loading

    func loadComments() {
        let videoId = (vm.playerInfo?.video ?? video).id
        vm.comments.load(videoId: videoId)
    }

}
