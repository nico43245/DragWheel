import AppKit
import Combine

/// The menu bar icon and its menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    override init() {
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "circle.hexagongrid.circle", accessibilityDescription: "DragWheel")
            button.image?.isTemplate = true
            button.toolTip = "DragWheel — hold Shift while dragging a file"
        }
        menu.delegate = self
        item.menu = menu
    }

    /// Rebuilt every time it opens so Recent, theme and permission state are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Hold ⇧ Shift while dragging a file", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if !DragMonitor.hasAccessibility {
            menu.addItem(entry("⚠︎ Grant Accessibility permission…", #selector(openAccessibility)))
        }
        if ExternalTool.ffmpeg.path == nil {
            let warn = NSMenuItem(title: "⚠︎ ffmpeg missing: brew install ffmpeg", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        menu.addItem(entry("Open Converter Window…", #selector(openConverter), key: "o"))

        let clipboard = NSMenuItem(title: "Convert Clipboard Image", action: nil, keyEquivalent: "")
        let clipMenu = NSMenu()
        for (title, action) in [("PNG", ActionID.toPNG), ("JPEG", .toJPEG), ("WEBP", .toWEBP), ("HEIC", .toHEIC), ("PDF", .toPDF), ("Text (OCR)", .ocrText)] {
            let sub = entry(title, #selector(convertClipboard(_:)))
            sub.representedObject = action.rawValue
            clipMenu.addItem(sub)
        }
        clipboard.submenu = clipMenu
        menu.addItem(clipboard)

        let recent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let items = History.shared.items.prefix(10)
        if items.isEmpty {
            let none = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentMenu.addItem(none)
        }
        for h in items {
            let title = h.output.map { "✓ \($0.lastPathComponent)" } ?? "✗ \(h.source.lastPathComponent) — \(Catalog.action(h.action).title)"
            let row = entry(title, h.output == nil ? nil : #selector(revealRecent(_:)))
            row.representedObject = h.output
            row.toolTip = h.error
            recentMenu.addItem(row)
        }
        recent.submenu = recentMenu
        menu.addItem(recent)

        let themes = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in Theme.all {
            let row = entry("\(theme.emoji)  \(theme.name)", #selector(pickTheme(_:)))
            row.representedObject = theme.id
            row.state = theme.id == Settings.shared.themeID ? .on : .off
            themeMenu.addItem(row)
        }
        themes.submenu = themeMenu
        menu.addItem(themes)

        menu.addItem(.separator())
        menu.addItem(entry("Preferences…", #selector(openPreferences), key: ","))
        menu.addItem(entry("Quit DragWheel", #selector(quit), key: "q"))
    }

    private func entry(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func openConverter() { ConverterWindow.show() }
    @objc private func openPreferences() { PreferencesWindow.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openAccessibility() {
        DragMonitor.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func convertClipboard(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ActionID(rawValue: raw) else { return }
        Task { await ConversionEngine.shared.convertClipboard(to: action) }
    }

    @objc private func revealRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc private func pickTheme(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Settings.shared.themeID = id }
    }
}
