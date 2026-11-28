import SwiftUI
import Observation

enum DownloadMode: String, CaseIterable, Identifiable {
    case video, audio
    var id: String { rawValue }
    var title: String { self == .video ? "Video" : "Audio" }
}

struct DownloadItem: Identifiable {
    enum State { case starting, downloading, finished, failed, cancelled }
    let id = UUID().uuidString
    var url: String
    var title: String
    var state: State = .starting
    var progress: Double = 0
    var speed: Double?
    var eta: Int?
    var files: [String] = []
    var message: String?

    var isActive: Bool { state == .starting || state == .downloading }
}

struct FormatInfo: Identifiable, Decodable, Hashable {
    let id: String
    let ext: String?
    let resolution: String?
    let height: Int?
    let vcodec: String?
    let acodec: String?
    let filesize: Int?
    let tbr: Double?
    let note: String?

    var hasVideo: Bool { vcodec != nil && vcodec != "none" }
    var hasAudio: Bool { acodec != nil && acodec != "none" }
}

struct MediaInfo: Decodable {
    let title: String
    let uploader: String?
    let thumbnail: String?
    let duration: Double?
    let isPlaylist: Bool
    let count: Int?
    let formats: [FormatInfo]
    let warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case title, uploader, thumbnail, duration, count, formats, warnings
        case isPlaylist = "is_playlist"
    }
}

@Observable @MainActor
final class DownloadManager {
    var items: [DownloadItem] = []
    var version = "loading…"
    var bootError: String?
    var updateStatus = ""
    var isUpdating = false
    private var polling = false

    // MARK: boot / info

    func boot() async {
        do {
            let data = try await Py.call("version")
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            version = obj?["version"] as? String ?? "?"
        } catch {
            bootError = error.localizedDescription
            version = "unavailable"
        }
    }

    func fetchInfo(url: String) async throws -> MediaInfo {
        let data = try await Py.call("extract_info", ["url": url])
        return try JSONDecoder().decode(MediaInfo.self, from: data)
    }

    // MARK: downloads

    func start(url: String, mode: DownloadMode, formatID: String? = nil, title: String? = nil) {
        let item = DownloadItem(url: url, title: title ?? url)
        items.insert(item, at: 0)

        var payload: [String: Any] = [
            "id": item.id,
            "url": url,
            "mode": mode.rawValue,
            "custom_args": UserDefaults.standard.string(forKey: "customArgs") ?? "",
        ]
        if let formatID { payload["format_id"] = formatID }

        Task {
            do {
                _ = try await Py.call("start_download", payload)
                startPolling()
            } catch {
                update(item.id) { $0.state = .failed; $0.message = error.localizedDescription }
            }
        }
    }

    func cancel(_ id: String) {
        Task { _ = try? await Py.call("cancel", ["id": id]) }
    }

    private func update(_ id: String, _ change: (inout DownloadItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[i])
    }

    private func startPolling() {
        guard !polling else { return }
        polling = true
        UIApplication.shared.isIdleTimerDisabled = true   // iOS suspends us if the screen locks
        Task {
            while items.contains(where: { $0.isActive }) {
                if let data = try? await Py.call("drain_events"),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let events = obj["events"] as? [[String: Any]] {
                    events.forEach(apply)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            polling = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func apply(_ event: [String: Any]) {
        guard let id = event["id"] as? String, let type = event["type"] as? String else { return }
        update(id) { item in
            switch type {
            case "progress":
                item.state = .downloading
                if let t = event["title"] as? String { item.title = t }
                if let done = event["downloaded"] as? Double, let total = event["total"] as? Double, total > 0 {
                    item.progress = min(done / total, 1)
                }
                item.speed = event["speed"] as? Double
                item.eta = event["eta"] as? Int
            case "done":
                item.state = .finished
                item.progress = 1
                item.files = event["files"] as? [String] ?? []
            case "error":
                item.state = .failed
                item.message = event["text"] as? String
            case "cancelled":
                item.state = .cancelled
            case "log":
                item.message = event["text"] as? String
            default: break
            }
        }
    }

    // MARK: yt-dlp updater

    func checkForUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        updateStatus = "Checking PyPI…"
        Task {
            defer { isUpdating = false }
            do {
                let data = try await Py.call("update")
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                if obj["up_to_date"] as? Bool == true {
                    updateStatus = "Already on the latest version (\(obj["version"] as? String ?? "?"))."
                } else if let v = obj["installed"] as? String {
                    updateStatus = "Installed \(v). Fully quit and reopen the app to use it."
                }
            } catch {
                updateStatus = "Update failed: \(error.localizedDescription)"
            }
        }
    }
}
