import SmartTubeIOSCore
import SwiftUI

extension PlayerControlsOverlay {
    var chapterMarkers: some View {
        GeometryReader { geo in
            let hPad: CGFloat = 20
            let trackW = geo.size.width - hPad * 2
            ForEach(vm.chapters) { chapter in
                let x = hPad + trackW * CGFloat(chapter.startTime / max(vm.duration, 1))
                ZStack {
                    // Invisible enlarged hit area
                    Color.clear
                        .frame(width: 24, height: 44)
                    // Visible tick
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2, height: 12)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !vm.isScrubbing else { return }
                    vm.seek(to: chapter.startTime)
                }
                .position(x: x, y: geo.size.height / 2)
            }
        }
    }

    // SponsorBlock segment markers on the progress bar
    var sponsorBlockMarkers: some View {
        GeometryReader { geo in
            let hPad: CGFloat = 20
            let trackW = geo.size.width - hPad * 2
            ForEach(vm.sponsorSegments) { seg in
                let x = hPad + trackW * CGFloat(seg.start / max(vm.duration, 1))
                let width = trackW * CGFloat((seg.end - seg.start) / max(vm.duration, 1))
                Rectangle()
                    .fill(seg.category.color.opacity(0.8))
                    .frame(width: max(width, 2), height: 4)
                    .position(x: x + width / 2, y: geo.size.height / 2)
            }
        }
    }
}
