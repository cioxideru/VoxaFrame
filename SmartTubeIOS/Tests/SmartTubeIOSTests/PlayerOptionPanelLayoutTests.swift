import SwiftUI
import Testing

@testable import SmartTubeIOS

@Suite("Player panel layout")
@MainActor
struct PlayerOptionPanelLayoutTests {
    @Test("Reading panels request readable width; option menus keep their compact width")
    func idealWidths() throws {
        let options = PlayerOptionPanel(title: Text("Options"), isPresented: .constant(true)) {
            Color.clear.frame(height: 100)
        }
        let reading = PlayerOptionPanel(
            title: Text("Description"), isPresented: .constant(true), preferredWidth: VFColumn.readableMaximum
        ) {
            Color.clear.frame(height: 100)
        }
        #expect(try renderedWidth(options, width: nil) == 360)
        #expect(try renderedWidth(reading, width: nil) == VFColumn.readableMaximum)
    }

    @Test("Reading panels accept the width of narrow windows", arguments: [320.0, 375.0, 507.0])
    func narrowWindows(width: CGFloat) throws {
        let panel = CommentsPanel(comments: [], isLoading: false, isPresented: .constant(true))
        #expect(try renderedWidth(panel, width: width) == width)
    }

    @Test("Long reading content stays inside the proposed viewport")
    func longContentViewport() throws {
        let panel = PlayerOptionPanel(
            title: Text("Description"), isPresented: .constant(true), preferredWidth: VFColumn.readableMaximum
        ) {
            ScrollView {
                Text(String(repeating: "A long description with a channel, links and timestamps.\n", count: 200))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        let renderer = ImageRenderer(content: panel)
        renderer.proposedSize = ProposedViewSize(width: VFColumn.readableMaximum, height: 400)
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(VFColumn.readableMaximum))
        #expect(image.height == 400)
    }

    private func renderedWidth(_ view: some View, width: CGFloat?) throws -> CGFloat {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: 400)
        return CGFloat(try #require(renderer.cgImage).width)
    }
}
