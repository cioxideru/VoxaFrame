import SmartTubeIOSCore
import SwiftUI

// MARK: - AddRSSFeedView

/// Sheet that lets the user add a new RSS feed URL.

struct AddRSSFeedView: View {
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    @State private var isAdding = false
    @FocusState private var focusedField: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field { case title, url }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tech Reviews", text: $feedTitle)
                        .focused($focusedField, equals: .title)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .url }
                        .accessibilityIdentifier("rss.addFeed.titleField")
                        .visibleLabel("Title")
                    TextField("youtube.com/feeds/videos.xml?channel_id=…", text: $feedURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                        #endif
                        .focused($focusedField, equals: .url)
                        .submitLabel(.done)
                        .onSubmit(addFeed)
                        .accessibilityIdentifier("rss.addFeed.urlField")
                        .visibleLabel("Feed URL")
                } header: {
                    Text("Feed Details")
                } footer: {
                    // Said while typing, not only after Add.
                    if !feedURL.isEmpty, validURL == nil {
                        Label {
                            Text("Needs an address that starts with http:// or https://", bundle: .module)
                        } icon: {
                            Image(systemName: AppSymbol.warning)
                        }
                        .foregroundStyle(VFColor.danger)
                    }
                }

                Section {
                    Text(
                        "YouTube RSS feed URLs look like:\n**youtube.com/feeds/videos.xml?channel_id=…**\n\nYou can also find a channel's RSS feed via their channel page URL."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add RSS Feed")
            #if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) { addButton }
            }
        }
    }

    private var addButton: some View {
        Group {
            if isAdding {
                ProgressView()
            } else {
                Button {
                    addFeed()
                } label: {
                    Text("Add", bundle: .module)
                }
                .disabled(!canAdd)
                .accessibilityIdentifier(AccessibilityID.rssAddFeedConfirm)
            }
        }
    }

    /// The typed address when it is an http(s) URL.
    private var validURL: URL? {
        let trimmed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https" || url.scheme == "http", url.host != nil
        else { return nil }
        return url
    }

    private var canAdd: Bool {
        validURL != nil && !feedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAdding
    }

    private func addFeed() {
        let trimmedTitle = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAdd, let url = validURL else { return }

        isAdding = true

        Task {
            let feed = RSSFeedInfo(title: trimmedTitle, feedURL: url)
            await RSSFeedStore.shared.addFeed(feed)
            dismiss()
        }
    }
}

extension View {
    /// Shows `title` next to a field, so the field is not named by its placeholder alone.
    fileprivate func visibleLabel(_ title: LocalizedStringKey) -> some View {
        LabeledContent {
            self
        } label: {
            Text(title, bundle: .module)
        }
    }
}
