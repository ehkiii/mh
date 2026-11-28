import SwiftUI

struct DownloadedView: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(\.scenePhase) private var scenePhase
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var pending: [DownloadedFile] = []
    @State private var showConfirm = false

    private var library: Library { manager.library }
    private var selectedFiles: [DownloadedFile] { library.files.filter { selection.contains($0.id) } }

    var body: some View {
        Group {
            if library.files.isEmpty {
                ContentUnavailableView("Nothing downloaded yet",
                                       systemImage: "tray",
                                       description: Text("Finished downloads show up here."))
            } else {
                list
            }
        }
        .background(AppBackground())
        .navigationTitle("Downloaded")
        .toolbar { toolbarContent }
        .confirmationDialog(confirmTitle, isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) { pending = [] }
        } message: {
            Text("\(sizeText(pending)) will be removed from the Downloads folder too.")
        }
        .alert("Couldn't delete everything", isPresented: errorBinding) {
            Button("OK") {}
        } message: {
            Text(library.deleteError ?? "")
        }
        .onAppear { library.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { library.refresh() }   // may have changed in the Files app
        }
    }

    // MARK: list

    private var list: some View {
        List(selection: $selection) {
            ForEach(library.files) { file in
                DownloadedRow(file: file, editing: editMode.isEditing)
                    .tag(file.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) { ask([file]) }
                    }
                    .contextMenu {
                        ShareLink(item: file.url)
                        Button("Delete", systemImage: "trash", role: .destructive) { ask([file]) }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .refreshable { library.refresh() }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                selection.removeAll()
            }
            .disabled(library.files.isEmpty)
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if editMode.isEditing {
                Button("Delete selected", systemImage: "trash", role: .destructive) {
                    ask(selectedFiles)
                }
                .disabled(selection.isEmpty)
            }
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Select all", systemImage: "checkmark.circle") {
                    withAnimation { editMode = .active }
                    selection = Set(library.files.map(\.id))
                }
                Button("Delete all", systemImage: "trash", role: .destructive) {
                    ask(library.files)
                }
            }
            .disabled(library.files.isEmpty)
        }
    }

    // MARK: deleting

    private func ask(_ files: [DownloadedFile]) {
        guard !files.isEmpty else { return }
        pending = files
        showConfirm = true
    }

    private func performDelete() {
        library.delete(pending)
        selection.subtract(pending.map(\.id))
        pending = []
        if library.files.isEmpty { editMode = .inactive }
    }

    private var confirmTitle: String {
        pending.count == 1 ? "Delete “\(pending[0].displayName)”?" : "Delete \(pending.count) downloads?"
    }

    private func sizeText(_ files: [DownloadedFile]) -> String {
        ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }, countStyle: .file)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { library.deleteError != nil },
                set: { if !$0 { library.deleteError = nil } })
    }
}

struct DownloadedRow: View {
    let file: DownloadedFile
    let editing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.isAudio ? "music.note" : "film")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName).font(.headline).lineLimit(2)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            if !editing {
                ShareLink(item: file.url)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        [file.ext.uppercased(),
         ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file),
         file.date.formatted(date: .abbreviated, time: .shortened)]
            .joined(separator: " · ")
    }
}
