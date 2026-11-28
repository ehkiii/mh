import Foundation
import Observation

struct DownloadedFile: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let date: Date

    var id: String { url.path }
    var ext: String { url.pathExtension.lowercased() }
    var isAudio: Bool { ["m4a", "mp3", "aac", "opus", "ogg", "wav", "flac"].contains(ext) }

    /// "Some Title [abc123].mp4" -> "Some Title"
    var displayName: String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"\s*\[[^\]]+\]$"#, with: "", options: .regularExpression)
    }
}

/// The finished downloads. The Downloads folder is the source of truth, so this
/// survives app restarts and matches what the Files app shows.
@Observable @MainActor
final class Library {
    var files: [DownloadedFile] = []
    var unseen = 0                 // finished since the Downloaded tab was last opened
    var deleteError: String?
    /// File names still being written (a merge in progress), hidden from the list.
    var inFlight: Set<String> = []

    private static let mediaExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv",
        "m4a", "mp3", "aac", "opus", "ogg", "wav", "flac",
    ]

    func refresh() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Py.downloadsDir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        files = urls.compactMap { url -> DownloadedFile? in
            let name = url.lastPathComponent
            guard Self.mediaExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            guard !inFlight.contains(name) else { return nil }
            // loose pieces of a merged download: "Title [id].f137.mp4"
            if name.range(of: #"\]\.f[0-9A-Za-z_-]+\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil {
                return nil
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile ?? true else { return nil }
            return DownloadedFile(url: url,
                                  size: Int64(values?.fileSize ?? 0),
                                  date: values?.contentModificationDate ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    /// Deletes the files from disk (the Downloads folder), then refreshes the list.
    func delete(_ targets: [DownloadedFile]) {
        var failed = 0
        for file in targets {
            do {
                try FileManager.default.removeItem(at: file.url)
            } catch {
                if FileManager.default.fileExists(atPath: file.url.path) { failed += 1 }
            }
        }
        refresh()
        if failed > 0 {
            deleteError = failed == 1 ? "1 file couldn't be deleted." : "\(failed) files couldn't be deleted."
        }
    }
}
