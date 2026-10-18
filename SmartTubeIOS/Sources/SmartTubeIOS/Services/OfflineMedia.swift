import AVFoundation
import Foundation
import SmartTubeIOSCore

@MainActor
protocol OfflineMediaPreparing {
    func item(video: Video) async throws -> AVPlayerItem
}

struct OfflineMediaPreparer: OfflineMediaPreparing {
    func item(video: Video) async throws -> AVPlayerItem { try await OfflineMedia.item(video: video) }
}

/// AVFoundation loads media metadata asynchronously; no file reads run on the UI actor.
enum OfflineMedia {
    static func validate(_ url: URL, track: OfflineTrack, systemPackage: Bool) async throws {
        guard url.isFileURL else { throw OfflineLibraryError.invalidFile }
        let asset = AVURLAsset(url: url.absoluteURL)
        if systemPackage {
            guard OfflineLibraryStore.isSystemPackage(url) else { throw OfflineLibraryError.invalidFile }
            try validateOfflineCache(asset)
            return
        }
        let type: AVMediaType = [.audio, .translation].contains(track.kind) ? .audio : .video
        guard try await !asset.loadTracks(withMediaType: type).isEmpty else { throw OfflineLibraryError.invalidFile }
        if track.hasAudio {
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                throw OfflineLibraryError.missingAudio
            }
        }
    }

    private static func validateOfflineCache(_ asset: AVURLAsset) throws {
        #if os(iOS)
        guard asset.assetCache?.isPlayableOffline == true else { throw OfflineLibraryError.invalidFile }
        #else
        throw OfflineLibraryError.invalidFile
        #endif
    }

    @MainActor static func item(video: Video) async throws -> AVPlayerItem {
        guard let url = video.localFileURL, validLocalURL(url) else { throw OfflineLibraryError.invalidFile }
        let asset = AVURLAsset(url: url)
        if url.pathExtension == "movpkg" {
            guard video.localAudioFileURL == nil else { throw OfflineLibraryError.unavailable }
            try validateOfflineCache(asset)
            // Choose cached audio explicitly; the online master may default to an unsaved language.
            let group = try await asset.loadMediaSelectionGroup(for: .audible)
            let item = AVPlayerItem(asset: asset)
            if let group {
                guard let option = asset.assetCache?.mediaSelectionOptions(in: group).first else {
                    throw OfflineLibraryError.missingAudio
                }
                item.select(option, in: group)
            }
            return item
        }
        guard let audioURL = video.localAudioFileURL else {
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
                throw OfflineLibraryError.invalidFile
            }
            return AVPlayerItem(asset: asset)
        }
        guard validLocalURL(audioURL) else { throw OfflineLibraryError.invalidFile }
        let audio = AVURLAsset(url: audioURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
            let audioTrack = try await audio.loadTracks(withMediaType: .audio).first
        else { throw OfflineLibraryError.invalidFile }
        let composition = AVMutableComposition()
        let videoDuration = try await asset.load(.duration)
        let audioDuration = try await audio.load(.duration)
        guard
            let composedVideo = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let composedAudio = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw OfflineLibraryError.invalidFile
        }
        try composedVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration), of: videoTrack, at: .zero)
        composedVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        try composedAudio.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTimeMinimum(videoDuration, audioDuration)), of: audioTrack, at: .zero)
        return AVPlayerItem(asset: composition)
    }

    static func validLocalURL(_ url: URL) -> Bool {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return OfflineLibraryStore.contains(url, in: documents.appendingPathComponent("SmartTubeOffline"))
            || OfflineLibraryStore.contains(url, in: documents.appendingPathComponent("SmartTubeDownloads"))
            || OfflineLibraryStore.isSystemPackage(url)
    }
}
