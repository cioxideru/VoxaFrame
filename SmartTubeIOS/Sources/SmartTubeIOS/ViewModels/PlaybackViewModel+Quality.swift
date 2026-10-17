import AVFoundation
import SmartTubeIOSCore
import os

private let qualityLog = ViewModelLogger(category: "Quality")

// MARK: - Stream Format / HLS Quality Selection (thin wrapper — logic lives in PlaybackQualityManager)

extension PlaybackViewModel {

    public func selectFormat(_ format: VideoFormat?) {
        if let fmt = format {
            qualityLog.notice(
                "[quality] selectFormat → \(fmt.qualityLabel) (\(fmt.codecShortLabel)) \(fmt.width)×\(fmt.height)@\(fmt.fps)fps"
            )
        } else {
            qualityLog.notice("[quality] selectFormat → Auto (clearing selectedFormat)")
        }
        qualityManager.selectFormat(format)
        // Refresh Stats for Nerds immediately so the overlay shows the new quality
        // without waiting for the next periodic-observer tick (which may not fire
        // while the player is loading the replacement item).
        if statsForNerdsVisible { updateStatsSnapshot() }
    }

    /// The last explicit choice, or the default for settings saved before that choice existed.
    var effectiveQuality: VideoQualityPreference {
        qualityManager.effectiveQuality
    }

    func reloadHLSItem(seekTo time: TimeInterval, quality: VideoQualityPreference) {
        qualityManager.reloadHLSItem(seekTo: time, quality: quality)
    }

    func fetchHLSVariantURLs(url: URL) async -> [Int: URL] {
        await qualityManager.fetchHLSVariantURLs(url: url)
    }

    static func deduplicatedVideoFormats(_ formats: [VideoFormat]) -> [VideoFormat] {
        PlaybackQualityManager.deduplicatedVideoFormats(formats)
    }

    func peakBitRate(for height: Int) -> Double {
        PlaybackQualityManager.peakBitRate(for: height)
    }

    func reloadHLSItemH264Capped(seekTo time: TimeInterval) async {
        await qualityManager.reloadHLSItemH264Capped(seekTo: time)
    }
}
