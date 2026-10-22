import AppKit

/// Watches the system for "a file is being dragged and Shift went down" and summons the wheel.
///
/// Only modifier, mouse and scroll events are observed. The key monitor reacts to exactly
/// two keys (Tab and Esc) while the wheel is open and ignores everything else.
@MainActor
final class DragMonitor {
    static let shared = DragMonitor()

    private var monitors: [Any] = []
    private var dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var shiftWasDown = false

    func start() {
        stop()
        observe(.global, .leftMouseDown) { [weak self] _ in self?.mouseDown() }
        observe(.global, .flagsChanged) { [weak self] e in self?.flagsChanged(e) }
        observe(.global, .leftMouseDragged) { [weak self] e in self?.dragged(e) }
        observe(.global, .scrollWheel) { e in
            guard WheelPanel.shared.isShowing else { return }
            WheelState.shared.handleScroll(delta: e.scrollingDeltaY != 0 ? e.scrollingDeltaY : e.deltaY)
        }
        observe(.global, .keyDown) { [weak self] e in _ = self?.keyDown(e) }
        // Same, when one of our own windows is in front.
        observe(.local, .flagsChanged) { [weak self] e in self?.flagsChanged(e) }
        intercept(.local, .keyDown) { [weak self] e in self?.keyDown(e) ?? e }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: Events

    private func mouseDown() {
        dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    }

    private func flagsChanged(_ event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        defer { shiftWasDown = shift }
        guard shift, !shiftWasDown else { return }   // react to the press, not the release

        if WheelPanel.shared.isShowing {
            WheelState.shared.nextPage()             // tap Shift again to cycle pages
        } else {
            summonIfDraggingFiles(toolsPage: event.modifierFlags.contains(.option))
        }
    }

    private func dragged(_ event: NSEvent) {
        guard event.modifierFlags.contains(.shift), !WheelPanel.shared.isShowing else { return }
        summonIfDraggingFiles(toolsPage: event.modifierFlags.contains(.option))
    }

    private func keyDown(_ event: NSEvent) -> NSEvent? {
        guard WheelPanel.shared.isShowing else { return event }
        switch event.keyCode {
        case 48: // Tab
            event.modifierFlags.contains(.shift) ? WheelState.shared.previousPage() : WheelState.shared.nextPage()
            return nil
        case 53: // Esc
            WheelPanel.shared.hide()
            return nil
        default:
            return event
        }
    }

    /// The wheel appears only when the mouse is down *and* a new file drag has started,
    /// so Shift-clicking or Shift-selecting text never triggers it.
    private func summonIfDraggingFiles(toolsPage: Bool) {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { log.debug("shift: mouse not down"); return }
        let drag = NSPasteboard(name: .drag)
        guard drag.changeCount != dragChangeCountAtMouseDown else { log.debug("shift: no new drag"); return }
        let files = drag.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !files.isEmpty else { log.debug("shift: drag has no files"); return }
        log.info("wheel shown for \(files.count) file(s)")
        WheelPanel.shared.show(files: files, toolsPage: toolsPage)
    }

    // MARK: Plumbing

    private enum Scope { case global, local }

    private func observe(_ scope: Scope, _ mask: NSEvent.EventTypeMask, _ handler: @escaping @MainActor (NSEvent) -> Void) {
        intercept(scope, mask) { (e: NSEvent) -> NSEvent? in handler(e); return e }
    }

    private func intercept(_ scope: Scope, _ mask: NSEvent.EventTypeMask, _ handler: @escaping @MainActor (NSEvent) -> NSEvent?) {
        let monitor: Any?
        switch scope {
        case .global:
            monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { e in
                MainActor.assumeIsolated { _ = handler(e) }
            }
        case .local:
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { e in
                MainActor.assumeIsolated { handler(e) }
            }
        }
        if let monitor { monitors.append(monitor) }
    }
}
