import Testing

@testable import SmartTubeIOSCore

// Upstream #194: Home opens with the first chip of Settings › Visible Sections, not always with Home.

@Suite("Home start section follows the visible sections (#194)")
struct HomeStartSectionTests {

    private func start(_ enabled: [BrowseSection.SectionType], hideShorts: Bool = false) -> BrowseSection.SectionType {
        BrowseSection.homeStartSection(in: BrowseSection.homeSections(enabled: enabled, hideShorts: hideShorts)).type
    }

    @Test("Default settings open Home")
    func defaultsOpenHome() {
        #expect(start(AppSettings().enabledSections) == .home)
        #expect(start([]) == .home)
    }

    @Test("A section moved above Home opens first")
    func reorderedHome() {
        #expect(start([.subscriptions, .home, .history]) == .subscriptions)
    }

    @Test("Hidden Home opens the first visible section")
    func hiddenHome() {
        #expect(start([.history, .playlists]) == .history)
    }

    @Test("Hidden Shorts in first place open the next visible section")
    func hiddenShortsFirst() {
        #expect(start([.shorts, .music, .home], hideShorts: true) == .music)
        #expect(start([.shorts, .music, .home], hideShorts: false) == .shorts)
    }

    @Test("A list that the Shorts filter empties keeps Home (coordinator Q-1)")
    func filteredToNothingKeepsHome() {
        #expect(BrowseSection.homeSections(enabled: [.shorts], hideShorts: true).isEmpty)
        #expect(start([.shorts], hideShorts: true) == .home)
    }

    @Test("The visible list keeps the saved order and drops unknown retired types")
    func visibleOrder() {
        let types = BrowseSection.homeSections(enabled: [.news, .recommended, .home], hideShorts: false).map(\.type)
        #expect(types == [.news, .home])
    }
}
