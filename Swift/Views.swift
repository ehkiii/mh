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
    @State private var mode: DownloadMode = .video
    @State private var showFormats = false
    @AppStorage("videoQuality") private var qualityRaw = VideoQuality.best.rawValue
    @AppStorage("audioFormat") private var audioRaw = AudioFormat.m4a.rawValue

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
        .sheet(isPresented: $showFormats) {
            FormatPickerView(url: trimmed, mode: mode)
                .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var optionsRow: some View {
        HStack(spacing: 12) {
            if mode == .video {
                Menu {
                    Picker("Quality", selection: $qualityRaw) {
                        ForEach(VideoQuality.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } label: {
                    optionLabel("Quality", VideoQuality(rawValue: qualityRaw)?.title ?? "Best available")
                }
                optionLabel("Format", "MP4").opacity(0.7)
            } else {
                Menu {
                    Picker("Format", selection: $audioRaw) {
                        ForEach(AudioFormat.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Button("MP3 (needs ffmpeg, not built in yet)") {}
                        .disabled(true)
                } label: {
                    optionLabel("Format", AudioFormat(rawValue: audioRaw)?.title ?? "M4A (AAC)")
                }
            }
        }
    }

    private func optionLabel(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).bold().lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.interactive(), in: .capsule)
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
                    Button("Paste", systemImage: "doc.on.clipboard") {
                        urlText = UIPasteboard.general.string ?? urlText
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .glassEffect(.regular.interactive(), in: .capsule)

                Picker("Type", selection: $mode) {
                    ForEach(DownloadMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                optionsRow

                HStack(spacing: 12) {
                    Button {
                        manager.start(url: trimmed, mode: mode,
                                      quality: VideoQuality(rawValue: qualityRaw) ?? .best,
                                      audio: AudioFormat(rawValue: audioRaw) ?? .m4a)
                        urlText = ""
                    } label: {
                        Label("Download", systemImage: "arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        showFormats = true
                    } label: {
                        Label("Formats", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
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

// MARK: - Format picker

struct FormatPickerView: View {
    let url: String
    let mode: DownloadMode
    @Environment(DownloadManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State private var info: MediaInfo?
    @State private var error: String?
    @State private var showAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let info {
                    GlassEffectContainer(spacing: 12) {
                        VStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.title).font(.headline)
                                if let u = info.uploader {
                                    Text(u).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .glassCard()

                            if info.isPlaylist {
                                Text("Playlist with \(info.count ?? 0) items. Use Download to grab all of it.")
                                    .glassCard()
                            } else {
                                Toggle("Show all formats (video-only has no sound)", isOn: $showAll)
                                    .padding(.horizontal, 4)
                                if let warnings = info.warnings, !warnings.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("yt-dlp said").font(.footnote.bold())
                                        ForEach(warnings, id: \.self) {
                                            Text($0).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .glassCard(cornerRadius: 20)
                                }
                                if usable(info).isEmpty {
                                    Text(showAll
                                         ? "yt-dlp found no formats for this link."
                                         : "Nothing this app can save directly. Turn on “Show all formats” to see everything yt-dlp found.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                        .glassCard(cornerRadius: 20)
                                }
                                ForEach(usable(info)) { f in
                                    Button {
                                        manager.start(url: url, mode: mode, formatID: f.id, title: info.title)
                                        dismiss()
                                    } label: {
                                        FormatRow(format: f).glassCard(cornerRadius: 20, interactive: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding()
                    }
                } else if let error {
                    ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                        .padding(.top, 60)
                } else {
                    ProgressView("Fetching formats…").padding(.top, 80)
                }
            }
            .navigationTitle("Formats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
            .task { await load() }
        }
    }

    private func usable(_ info: MediaInfo) -> [FormatInfo] {
        let list: [FormatInfo]
        if showAll {
            list = info.formats
        } else if mode == .audio {
            list = info.formats.filter { $0.hasAudio && !$0.hasVideo }
        } else {
            // ready-made video+audio files, plus H.264 video that we merge with audio ourselves
            list = info.formats.filter { ($0.hasAudio && $0.hasVideo) || $0.isMuxableVideo }
        }
        return list.sorted { ($0.height ?? 0, $0.tbr ?? 0) > ($1.height ?? 0, $1.tbr ?? 0) }
    }

    private func load() async {
        do { info = try await manager.fetchInfo(url: url) }
        catch { self.error = error.localizedDescription }
    }
}

struct FormatRow: View {
    let format: FormatInfo
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(format.resolution ?? "audio only").font(.body)
                Text([format.ext, format.note, format.isMuxableVideo ? "+ best audio, merged" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let size = format.filesize {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
