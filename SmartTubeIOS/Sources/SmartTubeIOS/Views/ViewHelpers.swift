import SmartTubeIOSCore
import SwiftUI

// MARK: - ShortsPresentation
//
// Shared Identifiable wrapper used by BrowseView and ChannelView to present
// ShortsPlayerView via .fullScreenCover(item:).

struct ShortsPresentation: Identifiable {
    let id = UUID()
    let videos: [Video]
    let startIndex: Int
}

// MARK: - ChannelDestination
//
// Identifiable wrapper used to drive navigationDestination(item:) for channel navigation
// triggered by the .openChannel NotificationCenter event.

struct ChannelDestination: Identifiable, Hashable {
    let channelId: String
    var id: String { channelId }
}

// MARK: - Shared layout constants

/// tvOS: fixed 4 columns (flexible) — predictable across all TV sizes.
#if os(tvOS)
let videoGridColumns = [
    GridItem(.flexible(), spacing: 40),
    GridItem(.flexible(), spacing: 40),
    GridItem(.flexible(), spacing: 40),
    GridItem(.flexible(), spacing: 40),
]
let videoGridRowSpacing: CGFloat = 40
#else
let videoGridRowSpacing: CGFloat = 12

/// Fixed (not adaptive) columns avoid the rotation hit-test mismatch of issue #82.
func videoGridColumns(_ settings: AppSettings, landscape: Bool) -> [GridItem] {
    let count = landscape ? settings.gridColumnsLandscape : settings.gridColumnsPortrait
    return Array(repeating: GridItem(.flexible(), spacing: videoGridRowSpacing), count: count)
}
#endif

/// Videos per row in `VideoGridSection`: 1 in the compact list, otherwise its grid columns.
func videoGridColumnCount(_ settings: AppSettings, landscape: Bool) -> Int {
    guard !settings.compactThumbnails else { return 1 }
    #if os(tvOS)
    return videoGridColumns.count
    #else
    return videoGridColumns(settings, landscape: landscape).count
    #endif
}

/// `videoGridColumnCount` for a feed `width` points wide: one column at accessibility text sizes and, on iPad and
/// Mac, a column fewer rather than cards narrower than `VFMargin.cardMinWidth`. `width` 0 (not measured yet) keeps
/// the setting.
@MainActor
func videoGridColumnCount(
    _ settings: AppSettings, landscape: Bool, width: CGFloat, dynamicTypeSize: DynamicTypeSize
) -> Int {
    let preferred = videoGridColumnCount(settings, landscape: landscape)
    #if os(tvOS)
    return preferred
    #else
    if dynamicTypeSize.isAccessibilitySize { return 1 }
    #if os(iOS)
    guard UIDevice.current.userInterfaceIdiom == .pad else { return preferred }
    #endif
    guard width > 0 else { return preferred }
    let usable = width - 2 * (videoGridMargin ?? 0) + videoGridRowSpacing
    let fitting = Int(usable / (VFMargin.cardMinWidth + videoGridRowSpacing))
    return min(preferred, max(1, fitting))
    #endif
}

/// Side margin of card grids and shelves; `nil` (the system padding) on tvOS, whose safe area already insets content.
@MainActor
var videoGridMargin: CGFloat? {
    #if os(tvOS)
    return nil
    #elseif os(iOS)
    return UIDevice.current.userInterfaceIdiom == .pad ? VFMargin.ipad : VFMargin.iphone
    #else
    return VFMargin.mac
    #endif
}

// MARK: - Layout orientation

private struct IsLandscapeLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` when the root window is wider than tall; set by `RootView`.
    var isLandscapeLayout: Bool {
        get { self[IsLandscapeLayoutKey.self] }
        set { self[IsLandscapeLayoutKey.self] = newValue }
    }
}

// MARK: - Accent color

extension AppSettings.AccentColorChoice {
    /// iPhone and iPad: the design's light/dark pair for every choice (`VFColorPair.action(for:)`); System is the coral.
    /// macOS: `nil` keeps the user's system accent and the named choices are the system colours.
    /// tvOS: as macOS. White on the dark coral is 2.07:1 on an unfocused `.borderedProminent`, and so is coral on the white
    /// focus platter; switching needs a tvOS runtime or device to check focused and unfocused contrast (OQ-0019).
    public var color: Color? {
        #if os(iOS)
        return Self.prominentColors[self]?.fill
        #else
        switch self {
        case .system: return nil
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        }
        #endif
    }

    #if os(iOS)
    /// Label on a `color` fill (`.vfProminent`).
    var onColor: Color { Self.prominentColors[self]?.label ?? VFColor.onAction }

    /// Built once, so `.tint` gets an equal `Color` on every update.
    private static let prominentColors = Dictionary(
        uniqueKeysWithValues: allCases.map {
            ($0, (fill: Color(VFColorPair.action(for: $0)), label: Color(VFColorPair.onAction(for: $0))))
        })
    #endif

    var displayName: String {
        switch self {
        case .system: return String(localized: "Default", bundle: .module)
        case .red: return String(localized: "Red", bundle: .module)
        case .orange: return String(localized: "Orange", bundle: .module)
        case .yellow: return String(localized: "Yellow", bundle: .module)
        case .green: return String(localized: "Green", bundle: .module)
        case .mint: return String(localized: "Mint", bundle: .module)
        case .teal: return String(localized: "Teal", bundle: .module)
        case .blue: return String(localized: "Blue", bundle: .module)
        case .indigo: return String(localized: "Indigo", bundle: .module)
        case .purple: return String(localized: "Purple", bundle: .module)
        case .pink: return String(localized: "Pink", bundle: .module)
        }
    }

    /// Pre-tinted, because Picker menus re-tint template images with the current accent.
    var swatch: Image {
        #if canImport(UIKit)
        let tint = color.map { UIColor($0) } ?? UIColor(named: "AccentColor") ?? .systemBlue
        let base = UIImage(systemName: AppSymbol.colorSwatch) ?? UIImage()
        return Image(uiImage: base.withTintColor(tint, renderingMode: .alwaysOriginal))
        #else
        let tint = color.map { NSColor($0) } ?? .controlAccentColor
        let base = NSImage(systemSymbolName: AppSymbol.colorSwatch, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        return Image(nsImage: base ?? NSImage())
        #endif
    }
}

// MARK: - DownloadAlertItem

/// Shared alert payload used by views that trigger video downloads.
struct DownloadAlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

extension View {
    func feedbackAlert(item: Binding<DownloadAlertItem?>) -> some View {
        alert(
            item.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            )
        ) {
            Button("OK") { item.wrappedValue = nil }
        } message: {
            Text(item.wrappedValue?.message ?? "")
        }
    }
}

// MARK: - AppSymbol
//
// Single source of truth for SF Symbol names used across the app.
// Use these constants instead of raw strings in Image(systemName:) and Label(..., systemImage:).

enum AppSymbol {
    // MARK: - Feed, player menus and settings
    static let channelFilter = "line.3.horizontal.decrease.circle"
    // Video and Shorts card menus, badges and cover placeholders.
    static let more = "ellipsis"
    static let playNext = "text.insert"
    static let addToQueue = "text.badge.plus"
    static let copyToPlaylist = "rectangle.stack.badge.plus"
    static let moveToPlaylist = "arrow.right.circle"
    static let incognito = "eyeglasses"
    static let notInterested = "hand.raised"
    static let dontRecommendChannel = "person.slash"
    static let savedToWatchLater = "bookmark.fill"
    static let liveDot = "circle.fill"
    static let noCover = "play.rectangle"
    static let watchLaterPlaylist = "clock.fill"
    static let likedPlaylist = "hand.thumbsup.fill"
    /// `channelFilter` while at least one search filter is on.
    static let channelFilterActive = "line.3.horizontal.decrease.circle.fill"
    /// Copies a suggestion into the search field without searching.
    static let searchCompletion = "arrow.up.left"
    static let queue = "list.number"
    static let rssFeed = "dot.radiowaves.left.and.right"
    static let rssManage = "list.bullet.indent"
    static let add = "plus"
    static let chevronRight = "chevron.right"
    static let speedometer = "speedometer"
    static let videoQuality = "film.stack"
    static let audioTrack = "waveform"
    static let sleepTimer = "moon.zzz"
    static let skipForward = "forward.fill"
    static let undo = "arrow.uturn.backward"
    static let reportFlag = "flag"
    static let removeCircle = "minus.circle.fill"
    static let addCircle = "plus.circle.fill"
    static let personCircleMinus = "person.crop.circle.badge.minus"

    // MARK: - Navigation tabs
    static let home = "house.fill"
    static let search = "magnifyingglass"
    static let library = "square.stack.fill"
    static let settings = "gearshape.fill"
    // The other macOS Settings window tabs (with `skipForward` and `personCircle`).
    static let languages = "globe"
    static let appearance = "paintbrush"
    static let lock = "lock"

    // MARK: - Navigation / chevrons
    static let chevronLeft = "chevron.left"
    static let chevronUp = "chevron.up"
    static let chevronDown = "chevron.down"
    static let inspector = "sidebar.trailing"

    // MARK: - Playback controls
    static let play = "play.fill"
    static let pause = "pause.fill"
    static let muted = "speaker.slash.fill"
    static let speaker = "speaker.wave.2.fill"
    static let brightness = "sun.max.fill"
    static let verticalAdjustment = "arrow.up.and.down"
    static let videoFill = "arrow.up.left.and.arrow.down.right"
    static let videoFit = "arrow.down.right.and.arrow.up.left"
    static let previousTrack = "backward.end.fill"
    static let nextTrack = "forward.end.fill"
    static let previousChapter = "backward.end.alt.fill"
    static let nextChapter = "forward.end.alt.fill"
    static let thumbsUp = "hand.thumbsup"
    static let thumbsDown = "hand.thumbsdown"

    // MARK: - Actions
    static let checkmark = "checkmark"
    static let xmark = "xmark"
    static let xmarkCircle = "xmark.circle.fill"
    static let share = "square.and.arrow.up"
    static let openExternal = "arrow.up.right"
    static let copyDoc = "doc.on.doc"
    static let trash = "trash"
    static let deleteBackward = "delete.left"
    static let download = "arrow.down.to.line"
    static let retry = "arrow.clockwise"
    static let watchLater = "clock.badge"
    static let audioOnly = "waveform.circle"

    // MARK: - Status / info
    static let warning = "exclamationmark.triangle.fill"
    static let checkmarkCircle = "checkmark.circle.fill"
    static let clock = "clock"
    static let hourglass = "hourglass"
    static let questionCircle = "questionmark.circle"
    static let qrcode = "qrcode"
    static let sourceCode = "chevron.left.forwardslash.chevron.right"
    static let colorSwatch = "circle.fill"

    // MARK: - People / account
    static let personCircle = "person.crop.circle"
    static let personRectangle = "person.crop.rectangle"
    static let personCircleQuestion = "person.crop.circle.badge.questionmark"
    static let personCircleWarning = "person.crop.circle.badge.exclamationmark"
    static let followChannels = "person.badge.plus"
    static let subscribed = "checkmark.circle"

    // MARK: - Content
    static let stackLayers = "square.stack"
    static let film = "film"
    static let translation = "character.bubble"
    static let tvMediabox = "tv.and.mediabox"
    static let tvPlay = "play.tv"
}
