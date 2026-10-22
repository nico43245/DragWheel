import AppKit
import SwiftUI

/// A borderless, transparent panel that floats under the cursor and accepts the file drop.
@MainActor
final class WheelPanel: NSPanel, NSDraggingDestination {
    static let shared = WheelPanel()

    let state = WheelState.shared
    private var releaseWatch: Timer?

    private init() {
        let size = WheelState.size
        super.init(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let host = NSHostingView(rootView: WheelView(state: state))
        host.frame = NSRect(x: 0, y: 0, width: size, height: size)
        contentView = host
        registerForDraggedTypes([.fileURL])
    }

    override var canBecomeKey: Bool { false }

    var isShowing: Bool { isVisible && alphaValue > 0 }

    /// Shows the wheel centred on the cursor (kept fully on screen).
    func show(files: [URL], toolsPage: Bool) {
        state.setFiles(files)
        state.pageIndex = toolsPage ? 1 : Catalog.bestPage(for: files)
        state.hovered = nil

        let size = WheelState.size
        let mouse = NSEvent.mouseLocation
        var origin = NSPoint(x: mouse.x - size / 2, y: mouse.y - size / 2)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - size)
            origin.y = min(max(origin.y, f.minY), f.maxY - size)
        }
        setFrameOrigin(origin)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            animator().alphaValue = 1
        }
        watchForRelease()
    }

    func hide() {
        releaseWatch?.invalidate()
        releaseWatch = nil
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
                self?.state.hovered = nil
            }
        })
    }

    /// Global mouse-up events aren't reliable during a Finder drag, so poll the button state.
    private func watchForRelease() {
        releaseWatch?.invalidate()
        releaseWatch = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    // Give performDragOperation a moment to run first.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.hide() }
                    self.releaseWatch?.invalidate()
                }
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        state.handleScroll(delta: event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY)
    }

    // MARK: NSDraggingDestination

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        log.debug("drag entered wheel")
        let urls = fileURLs(sender)
        if !urls.isEmpty { state.setFiles(urls) }
        track(sender)
        return .copy
    }

    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(sender)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        state.hovered = nil
    }

    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        state.hovered != nil
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        let files = urls.isEmpty ? state.files : urls
        guard let action = state.hoveredAction, !files.isEmpty else { hide(); return false }
        log.info("drop: \(action.id.rawValue, privacy: .public) on \(files.count) file(s)")
        hide()
        Task { await ConversionEngine.shared.perform(action.id, on: files) }
        return true
    }

    private func track(_ sender: NSDraggingInfo) {
        let p = sender.draggingLocation  // window coordinates, origin bottom-left
        state.updateHover(at: CGPoint(x: p.x, y: WheelState.size - p.y))
    }

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
}
