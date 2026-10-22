import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings = Settings.shared
    @State private var launchAtLogin = Settings.shared.launchAtLogin
    @State private var hasAccessibility = DragMonitor.hasAccessibility

    var body: some View {
        Form {
            Section("Output") {
                Picker("Save converted files", selection: $settings.outputLocation) {
                    ForEach(OutputLocation.allCases) { Text($0.title).tag($0) }
                }
                if settings.outputLocation == .customFolder {
                    HStack {
                        Text(settings.customFolderPath).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose…", action: chooseFolder)
                    }
                }
                VStack(alignment: .leading) {
                    Slider(value: $settings.quality, in: 20...100, step: 5) {
                        Text("Quality")
                    }
                    Text("\(Int(settings.quality))% — lower means smaller files (JPEG, HEIC, AVIF, WebP, video)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Behaviour") {
                Toggle("Play a sound when done", isOn: $settings.playSound)
                Toggle("Show results in Finder", isOn: $settings.revealAfterConvert)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in Settings.shared.launchAtLogin = on }
            }
            Section("Look") {
                Picker("Theme", selection: $settings.themeID) {
                    ForEach(Theme.all) { Text("\($0.emoji)  \($0.name)").tag($0.id) }
                }
                ThemeSwatches(selected: settings.themeID)
            }
            Section("Permissions & helpers") {
                LabeledContent("Accessibility (Tab / Esc on the wheel)") {
                    if hasAccessibility {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant…") {
                            DragMonitor.requestAccessibility()
                            hasAccessibility = DragMonitor.hasAccessibility
                        }
                    }
                }
                LabeledContent("ffmpeg (video & audio)") { toolStatus(.ffmpeg) }
                LabeledContent("cwebp (WebP)") { toolStatus(.cwebp) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 560)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            hasAccessibility = DragMonitor.hasAccessibility
        }
    }

    @ViewBuilder
    private func toolStatus(_ tool: ExternalTool) -> some View {
        if tool.path != nil {
            Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Text(tool.installHint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if panel.runModal() == .OK, let url = panel.url { settings.customFolderPath = url.path }
    }
}

struct ThemeSwatches: View {
    let selected: String
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Theme.all) { theme in
                Circle()
                    .fill(theme.accent)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(theme.id == selected ? Color.primary : .clear, lineWidth: 2).padding(-3))
                    .onTapGesture { Settings.shared.themeID = theme.id }
                    .help(theme.name)
            }
        }
    }
}

/// Hosts SwiftUI content in a normal titled window, reusing it if already open.
@MainActor
enum WindowHost {
    private static var windows: [String: NSWindow] = [:]

    static func show<Content: View>(id: String, title: String, content: () -> Content) {
        if let existing = windows[id] {
            existing.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum PreferencesWindow {
    @MainActor static func show() {
        WindowHost.show(id: "preferences", title: "DragWheel Preferences") { PreferencesView() }
    }
}
