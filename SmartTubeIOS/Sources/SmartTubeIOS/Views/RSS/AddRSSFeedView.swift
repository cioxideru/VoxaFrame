import SmartTubeIOSCore
import SwiftUI

// MARK: - AddRSSFeedView

/// Sheet that lets the user add a new RSS feed URL.

struct AddRSSFeedView: View {
    @State private var feedURL: String = ""
    @State private var feedTitle: String = ""
    @State private var isAdding = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Feed Title (e.g. Tech Reviews)", text: $feedTitle)
                        .accessibilityIdentifier("rss.addFeed.titleField")
                    TextField("RSS Feed URL", text: $feedURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                        #endif
                        .accessibilityIdentifier("rss.addFeed.urlField")
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
                    Button {
                        addFeed()
                    } label: {
                        if isAdding {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Adding…")
                            }
                        } else {
                            Text("Add Feed")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .disabled(validURL == nil || feedTitle.isEmpty || isAdding)
                    .accessibilityIdentifier("rss.addFeed.confirmButton")
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

    private func addFeed() {
        let trimmedTitle = feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = validURL else { return }

        isAdding = true

        Task {
            let feed = RSSFeedInfo(title: trimmedTitle, feedURL: url)
            await RSSFeedStore.shared.addFeed(feed)
            dismiss()
        }
    }
}
