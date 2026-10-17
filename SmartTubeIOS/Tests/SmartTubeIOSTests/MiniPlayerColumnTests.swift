import Foundation
import SwiftUI
import Testing

@testable import SmartTubeIOS

// MARK: - MiniPlayerColumnTests (PLAN-0027 stage 2a)
//
// The mini player sits over the tab content beside the iPad sidebar, never over it. Frames are
// physical (global); the padding is logical, so a right-to-left sidebar must become leading padding.

@Suite("Mini-player column beside the sidebar")
struct MiniPlayerColumnTests {
    /// 1194 pt wide shell; a 320 pt sidebar with its header inset 32 pt on both sides.
    private let wide = CGRect(x: 0, y: 0, width: 1194, height: 834)

    private func insets(
        shell: CGRect, content: ClosedRange<CGFloat>, header: CGRect?, _ direction: LayoutDirection
    ) -> (leading: CGFloat, trailing: CGFloat) {
        MiniPlayerColumn.insets(
            shell: shell, contentMinX: content.lowerBound, contentMaxX: content.upperBound,
            sidebarHeader: header, layoutDirection: direction)
    }

    @Test("Compact width, tab bar and no sidebar: no padding", arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func compact(direction: LayoutDirection) {
        let result = insets(
            shell: CGRect(x: 0, y: 0, width: 402, height: 874), content: 0...402, header: nil, direction)
        #expect(result.leading == 0)
        #expect(result.trailing == 0)
    }

    @Test("Docked sidebar on the left, left-to-right: leading padding is the sidebar width")
    func dockedLeftToRight() {
        let header = CGRect(x: 32, y: 100, width: 256, height: 1)
        let result = insets(shell: wide, content: 320...1194, header: header, .leftToRight)
        #expect(result.leading == 320)
        #expect(result.trailing == 0)
    }

    @Test("Docked sidebar on the right, right-to-left: still leading padding of the sidebar width")
    func dockedRightToLeft() {
        let header = CGRect(x: 906, y: 100, width: 256, height: 1)
        let result = insets(shell: wide, content: 0...874, header: header, .rightToLeft)
        #expect(result.leading == 320)
        #expect(result.trailing == 0)
    }

    @Test("Floating sidebar covers full-width content, left-to-right: header estimate gives the width")
    func floatingLeftToRight() {
        // Measured on an iPad Pro 11 in portrait: header 42...248, sidebar card ends near 280.
        let header = CGRect(x: 42, y: 103, width: 206, height: 1)
        let result = insets(
            shell: CGRect(x: 0, y: 32, width: 834, height: 1158), content: 0...834, header: header,
            .leftToRight)
        #expect(result.leading == 290)
        #expect(result.trailing == 0)
    }

    @Test("Floating sidebar on the right, right-to-left: mirrored estimate becomes leading padding")
    func floatingRightToLeft() {
        let header = CGRect(x: 586, y: 103, width: 206, height: 1)
        let result = insets(
            shell: CGRect(x: 0, y: 32, width: 834, height: 1158), content: 0...834, header: header,
            .rightToLeft)
        #expect(result.leading == 290)
        #expect(result.trailing == 0)
    }

    @Test("A shell that does not start at x = 0 measures from its own edge")
    func offsetShell() {
        let shell = CGRect(x: 100, y: 0, width: 600, height: 800)
        let header = CGRect(x: 132, y: 100, width: 256, height: 1)
        let result = insets(shell: shell, content: 420...700, header: header, .leftToRight)
        #expect(result.leading == 320)
        #expect(result.trailing == 0)
    }

    @Test("Nothing measured yet: no padding")
    func unmeasured() {
        let result = insets(shell: .zero, content: 0...0, header: nil, .leftToRight)
        #expect(result.leading == 0)
        #expect(result.trailing == 0)
    }
}
