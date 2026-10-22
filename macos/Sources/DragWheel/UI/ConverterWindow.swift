import SwiftUI
import UniformTypeIdentifiers

/// The desktop window: drop or pick many files, then click an action to run it on all of them.
struct ConverterView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var history = History.shared
    @State private var files: [URL] = []
    @State private var pageIndex = 0
    @State private var busy = false
    @State private var dropTargeted = false

    var body: some View {
        let theme = settings.theme
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                dropZone(theme)
                Picker("", selection: $pageIndex) {
                    ForEach(Catalog.pages) { Text($0.title.capitalized).tag($0.id) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                actionGrid(theme)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(minWidth: 460)

            Divider()
            recentList
                .frame(width: 260)
        }
        .frame(minWidth: 740, minHeight: 500)
        .tint(theme.accent)
    }

    // MARK: Drop zone

    private func dropZone(_ theme: Theme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(dropTargeted ? theme.accent : Color.secondary.opacity(0.5))
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent.opacity(dropTargeted ? 0.12 : 0.04)))
            if files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 30))
                    Text("Drop files here").font(.headline)
                    Button("Choose Files…", action: chooseFiles)
                }
                .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(files.count) file\(files.count == 1 ? "" : "s")").font(.headline)
                        Spacer()
                        Button("Add…", action: chooseFiles)
                        Button("Clear") { files.removeAll() }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(files, id: \.self) { url in
                                HStack(spacing: 6) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable().frame(width: 16, height: 16)
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                }
                                .font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
        }
        .frame(height: 170)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { add([url]) }
                }
            }
            return true
        }
    }

    // MARK: Actions

    private func actionGrid(_ theme: Theme) -> some View {
        let page = Catalog.pages[pageIndex]
        var actions = page.petals + [page.center]
        if pageIndex == 0 { actions.append(Catalog.action(.toBMP).withTitle("BMP", hint: "Uncompressed bitmap", symbol: "square.grid.3x3")) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(actions, id: \.id) { action in
                Button {
                    run(action.id)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: action.symbol).font(.system(size: 18, weight: .semibold))
                        Text(action.title).font(.system(size: 12, weight: .bold, design: .rounded))
                        Text(action.hint).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.bordered)
                .disabled(files.isEmpty || busy)
            }
        }
        .overlay {
            if busy { ProgressView().controlSize(.large) }
        }
    }

    private func run(_ action: ActionID) {
        busy = true
        let batch = files
        Task {
            await ConversionEngine.shared.perform(action, on: batch)
            busy = false
        }
    }

    private func add(_ urls: [URL]) {
        for url in urls where !files.contains(url) { files.append(url) }
        if let first = files.first { pageIndex = Catalog.bestPage(for: [first]) }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: Recent

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("Clear") { history.clear() }.disabled(history.items.isEmpty)
            }
            .padding([.horizontal, .top], 14)
            if history.items.isEmpty {
                Text("Converted files show up here.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
            List(history.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    if let output = item.output {
                        Text(output.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(Notifier.shared.sizeSummary(from: item.source, to: output))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(item.source.lastPathComponent) → \(Catalog.action(item.action).title)").lineLimit(1)
                        if let error = item.error {
                            Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                }
                .contextMenu {
                    if let output = item.output {
                        Button("Open") { NSWorkspace.shared.open(output) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                        Button("Move to Trash") { try? FileManager.default.trashItem(at: output, resultingItemURL: nil) }
                    }
                }
                .onTapGesture(count: 2) {
                    if let output = item.output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

extension WheelAction {
    func withTitle(_ title: String, hint: String, symbol: String) -> WheelAction {
        WheelAction(id: id, title: title, hint: hint, symbol: symbol)
    }
}

enum ConverterWindow {
    @MainActor static func show() {
        WindowHost.show(id: "converter", title: "DragWheel") { ConverterView() }
    }
}
