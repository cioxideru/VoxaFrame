import SmartTubeIOSCore
import SwiftUI

// MARK: - Comments panel
//
// The same container as the More menu (VF/Sheet): a sheet on iPhone, a popover on iPad and Mac
// (`playerOptionPanel(isPresented:)`), a trailing menu over the dimmed video on tvOS.

/// Header (Cancel, Comments) above the comments, drawn as one grouped card.
struct CommentsPanel: View {
    let comments: [Comment]
    let isLoading: Bool
    @Binding var isPresented: Bool

    var body: some View {
        PlayerOptionPanel(
            title: Text("Comments", bundle: .module), isPresented: $isPresented,
            cancelAccessibilityIdentifier: AccessibilityID.playerCommentsPanelCancel
        ) {
            ScrollView { CommentsList(comments: comments, isLoading: isLoading) }
                .background(VFColor.surface)
        }
        .accessibilityIdentifier(AccessibilityID.playerCommentsPanel)
    }
}

/// Loading, empty or grouped list of comments; shared by the panel and the Mac inspector. Put it in a `ScrollView`.
struct CommentsList: View {
    let comments: [Comment]
    let isLoading: Bool

    var body: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(VFSpace.s32)
        } else if comments.isEmpty {
            Text("No comments available.", bundle: .module)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(VFSpace.s32)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(comments) { comment in
                    if comment.id != comments.first?.id { Divider() }
                    CommentRowView(comment: comment)
                }
            }
            .background(VFColor.elevated, in: RoundedRectangle(cornerRadius: VFRadius.card, style: .continuous))
            .padding(VFSpace.s16)
            .frame(maxWidth: VFColumn.readableMaximum)
            .frame(maxWidth: .infinity)
        }
    }
}
