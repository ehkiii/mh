import SwiftUI

// Requires iOS / iPadOS 26 and Xcode 26 (Liquid Glass APIs).

// MARK: - Glass helpers

/// Colorful backdrop so the glass has something to refract.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var colors: [Color] {
        scheme == .dark
        ? [.indigo.opacity(0.9), .purple.opacity(0.7), .blue.opacity(0.8),
           .teal.opacity(0.6), .indigo, .pink.opacity(0.6),
           .blue.opacity(0.7), .purple.opacity(0.8), .teal.opacity(0.7)]
        : [.cyan.opacity(0.6), .blue.opacity(0.5), .purple.opacity(0.5),
           .mint.opacity(0.6), .white.opacity(0.8), .pink.opacity(0.5),
           .teal.opacity(0.5), .indigo.opacity(0.4), .orange.opacity(0.4)]
    }

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [[0, 0], [0.5, 0], [1, 0],
                     [0, 0.5], [0.6, 0.45], [1, 0.5],
                     [0, 1], [0.5, 1], [1, 1]],
            colors: colors
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// A padded Liquid Glass card.
    func glassCard(cornerRadius: CGFloat = 24, tint: Color? = nil, interactive: Bool = false) -> some View {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - Root

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Downloads", systemImage: "arrow.down.circle") {
                NavigationStack { DownloadsView() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)        // floating glass sidebar on iPad, tab bar on iPhone
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

// MARK: - Downloads

struct DownloadsView: View {
    @Environment(DownloadManager.self) private var manager
    @State private var urlText = ""
    @State private var previewURL = ""
    @State private var showPreview = false

    private var trimmed: String { urlText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                inputArea

                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        if manager.items.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "tray").font(.largeTitle)
                                Text("No downloads yet").font(.headline)
                                Text("Paste a link above to get started.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .glassCard()
                        }
                        ForEach(manager.items) { DownloadRow(item: $0) }
                    }
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Downloads")
        .toolbar {
            Button("Clear finished", systemImage: "trash") {
                manager.items.removeAll { !$0.isActive }
            }
            .disabled(!manager.items.contains { !$0.isActive })
        }
        .sheet(isPresented: $showPreview) {
            PreviewSheet(url: previewURL) { urlText = "" }
        }
    }

    private func openPreview() {
        guard !trimmed.isEmpty else { return }
        previewURL = trimmed
        showPreview = true
    }

    private var inputArea: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(.secondary)
                    TextField("Paste a video or playlist URL", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit(openPreview)
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        urlText = UIPasteboard.general.string ?? urlText
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .capsule)

                Button {
                    openPreview()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(trimmed.isEmpty)
            }
        }
    }
}

struct DownloadRow: View {
    @Environment(DownloadManager.self) private var manager
    let item: DownloadItem

    private var tint: Color? {
        switch item.state {
        case .finished: .green.opacity(0.25)
        case .failed: .red.opacity(0.25)
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.title).font(.headline).lineLimit(2)
                Spacer(minLength: 8)
                trailingControl
            }

            switch item.state {
            case .starting:
                ProgressView().controlSize(.small)
            case .downloading:
                ProgressView(value: item.progress).tint(.white)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            case .merging:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Merging video and audio…").font(.caption).foregroundStyle(.secondary)
                }
            case .finished:
                Label("Saved to Files › SealPad › Downloads", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            case .failed:
                Label(item.message ?? "Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            case .cancelled:
                Text("Cancelled").font(.caption).foregroundStyle(.secondary)
            }
        }
        .glassCard(tint: tint)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) {
                manager.items.removeAll { $0.id == item.id }
            }
        }
    }

    @ViewBuilder private var trailingControl: some View {
        if item.isActive && item.state != .merging {
            Button("Cancel", systemImage: "xmark.circle.fill") { manager.cancel(item.id) }
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        } else if item.state == .finished, let f = item.files.last {
            ShareLink(item: URL(fileURLWithPath: f))
                .labelStyle(.iconOnly)
        }
    }

    private var detail: String {
        var parts = ["\(Int(item.progress * 100))%"]
        if let s = item.speed {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file) + "/s")
        }
        if let e = item.eta { parts.append("\(e)s left") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Preview + choose what to download

struct Choice: Identifiable {
    let id: String          // yt-dlp format id
    let title: String
    let subtitle: String
    let size: Int?
}

extension FormatInfo {
    var audioRate: Double { abr ?? tbr ?? 0 }

    var heightLabel: String {
        guard let h = height else { return resolution ?? "Video" }
        if let fps, fps > 30 { return "\(h)p\(Int(fps.rounded()))" }
        return "\(h)p"
    }

    var codecName: String? {
        let c = ((hasVideo ? vcodec : acodec) ?? "").lowercased()
        if c.hasPrefix("avc1") || c.hasPrefix("h264") { return "H.264" }
        if c.hasPrefix("vp09") || c.hasPrefix("vp9") { return "VP9" }
        if c.hasPrefix("av01") { return "AV1" }
        if c.hasPrefix("hev1") || c.hasPrefix("hvc1") { return "HEVC" }
        if c.hasPrefix("mp4a") { return "AAC" }
        if c.hasPrefix("opus") { return "Opus" }
        return c.isEmpty ? nil : c
    }
}

struct PreviewSheet: View {
    let url: String
    var onStarted: () -> Void = {}
    @Environment(DownloadManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State private var info: MediaInfo?
    @State private var error: String?
    @State private var mode: DownloadMode = .video

    var body: some View {
        NavigationStack {
            ScrollView {
                if let info {
                    content(info).padding()
                } else if let error {
                    ContentUnavailableView {
                        Label("Couldn't load", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                    .padding(.top, 60)
                } else {
                    ProgressView("Fetching info…").padding(.top, 100)
                }
            }
            .background(AppBackground())
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
            .task { await load() }
        }
    }

    private func load() async {
        error = nil
        info = nil
        do { info = try await manager.fetchInfo(url: url) }
        catch { self.error = error.localizedDescription }
    }

    // MARK: content

    @ViewBuilder private func content(_ info: MediaInfo) -> some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                header(info)

                if info.isPlaylist {
                    playlistCard(info)
                } else {
                    Picker("Type", selection: $mode) {
                        ForEach(DownloadMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    let result = choices(info)
                    if result.ok.isEmpty { nothingCard(info) }
                    ForEach(result.ok) { choiceRow($0, info: info) }
                    if !result.blocked.isEmpty { blockedSection(result.blocked) }
                }
            }
        }
    }

    private func header(_ info: MediaInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let t = info.thumbnail, let u = URL(string: t) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: u) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else if phase.error != nil {
                                Rectangle().fill(.quaternary).overlay { Image(systemName: "photo") }
                            } else {
                                Rectangle().fill(.quaternary).overlay { ProgressView() }
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(alignment: .bottomTrailing) {
                        if let d = info.duration {
                            Text(Self.time(d))
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.6), in: .capsule)
                                .padding(8)
                        }
                    }
            }
            Text(info.title).font(.headline)
            if let u = info.uploader {
                Text(u).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .glassCard()
    }

    private func playlistCard(_ info: MediaInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Playlist · \(info.count ?? 0) items").font(.headline)
            Text("Pick one setting for every item. Choosing formats per item isn't supported yet.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    manager.start(url: url, mode: .video, title: info.title)
                    finish()
                } label: {
                    Label("All as video", systemImage: "film").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button {
                    manager.start(url: url, mode: .audio, title: info.title)
                    finish()
                } label: {
                    Label("All as audio", systemImage: "music.note").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .glassCard()
    }

    private func nothingCard(_ info: MediaInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing this app can save here").font(.headline)
            Text("Everything yt-dlp found needs ffmpeg or isn't a direct download. See the list below.")
                .font(.footnote).foregroundStyle(.secondary)
            if let w = info.warnings, !w.isEmpty {
                ForEach(w, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .glassCard(cornerRadius: 20)
    }

    private func choiceRow(_ c: Choice, info: MediaInfo) -> some View {
        Button {
            manager.start(url: url, mode: mode, formatID: c.id, title: info.title, noPlaylist: true)
            finish()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.headline)
                    if !c.subtitle.isEmpty {
                        Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let size = c.size {
                    Text("≈ " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.down.circle.fill").font(.title2)
            }
            .glassCard(cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func blockedSection(_ items: [Choice]) -> some View {
        DisclosureGroup("Also available, but needs ffmpeg (\(items.count))") {
            VStack(spacing: 10) {
                ForEach(items) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title)
                            if !c.subtitle.isEmpty {
                                Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                    .opacity(0.6)
                }
            }
            .padding(.top, 8)
        }
        .glassCard(cornerRadius: 20)
    }

    // MARK: building the list

    private func choices(_ info: MediaInfo) -> (ok: [Choice], blocked: [Choice]) {
        let aac = info.formats.filter { $0.isAAC }.max { $0.audioRate < $1.audioRate }
        var ok: [Choice] = []
        var blocked: [Choice] = []

        switch mode {
        case .video:
            let videos = info.formats.filter { $0.hasVideo }.sorted {
                ($0.height ?? 0, $0.fps ?? 0, $0.tbr ?? 0) > ($1.height ?? 0, $1.fps ?? 0, $1.tbr ?? 0)
            }
            for f in videos {
                let merged = !f.hasAudio
                let saveable = f.isHTTP && (!merged || (f.isMuxableVideo && aac != nil))
                var size = f.filesize
                if merged, let s = size { size = s + (aac?.filesize ?? 0) }
                let subtitle = [f.ext?.uppercased(), f.codecName, merged ? "merged with audio" : nil]
                    .compactMap { $0 }.joined(separator: " · ")
                let choice = Choice(id: f.id, title: f.heightLabel, subtitle: subtitle, size: size)
                if saveable { ok.append(choice) } else { blocked.append(choice) }
            }
        case .audio:
            let audios = info.formats.filter { $0.hasAudio && !$0.hasVideo }.sorted {
                ($0.isAAC ? 1 : 0, $0.audioRate) > ($1.isAAC ? 1 : 0, $1.audioRate)
            }
            for f in audios {
                var title = f.ext?.uppercased() ?? "Audio"
                if f.audioRate > 0 { title += " · \(Int(f.audioRate)) kbps" }
                let subtitle = [f.codecName, f.note].compactMap { $0 }.joined(separator: " · ")
                let choice = Choice(id: f.id, title: title, subtitle: subtitle, size: f.filesize)
                if f.isHTTP { ok.append(choice) } else { blocked.append(choice) }
            }
            blocked.append(Choice(id: "mp3", title: "MP3", subtitle: "Converting to MP3 needs ffmpeg", size: nil))
        }
        return (ok, blocked)
    }

    private func finish() {
        onStarted()
        dismiss()
    }

    private static func time(_ seconds: Double) -> String {
        let t = Int(seconds)
        let h = t / 3600, m = (t % 3600) / 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(DownloadManager.self) private var manager
    @AppStorage("customArgs") private var customArgs = ""

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("yt-dlp").font(.headline)
                        LabeledContent("Version", value: manager.version)
                        Button {
                            manager.checkForUpdates()
                        } label: {
                            Label(manager.isUpdating ? "Updating…" : "Check for updates",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(manager.isUpdating)

                        if !manager.updateStatus.isEmpty {
                            Text(manager.updateStatus).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let err = manager.bootError {
                            Text(err).font(.footnote).foregroundStyle(.red)
                        }
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Custom yt-dlp arguments").font(.headline)
                        TextField("--write-subs --sub-langs en", text: $customArgs, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                            .padding(12)
                            .background(.quaternary, in: .rect(cornerRadius: 14))
                        Text("Parsed like the command line and applied to every download. Options that need ffmpeg won't work yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .glassCard()
                }
            }
            .padding()
        }
        .background(AppBackground())
        .navigationTitle("Settings")
    }
}
