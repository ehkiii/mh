import AVFoundation

enum MuxError: LocalizedError {
    case missingTrack(String)
    case exportUnavailable

    var errorDescription: String? {
        switch self {
        case .missingTrack(let kind): return "No \(kind) track found in the downloaded file"
        case .exportUnavailable: return "This device can't merge these streams without re-encoding"
        }
    }
}

/// Lossless merge of a video-only and an audio-only file (H.264 + AAC) into one mp4.
enum Muxer {
    static func merge(video: URL, audio: URL, output: URL) async throws {
        let vAsset = AVURLAsset(url: video)
        let aAsset = AVURLAsset(url: audio)

        guard let vTrack = try await vAsset.loadTracks(withMediaType: .video).first
        else { throw MuxError.missingTrack("video") }
        guard let aTrack = try await aAsset.loadTracks(withMediaType: .audio).first
        else { throw MuxError.missingTrack("audio") }

        let vDuration = try await vAsset.load(.duration)
        let aDuration = try await aAsset.load(.duration)

        let composition = AVMutableComposition()
        let cv = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        try cv?.insertTimeRange(CMTimeRange(start: .zero, duration: vDuration), of: vTrack, at: .zero)
        cv?.preferredTransform = try await vTrack.load(.preferredTransform)

        let ca = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        let aLimit = CMTimeMinimum(vDuration, aDuration)
        try ca?.insertTimeRange(CMTimeRange(start: .zero, duration: aLimit), of: aTrack, at: .zero)

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        else { throw MuxError.exportUnavailable }

        try? FileManager.default.removeItem(at: output)
        try await export.export(to: output, as: .mp4)
    }
}
