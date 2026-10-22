import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.setUp()
        statusBar = StatusBarController()
        DragMonitor.shared.start()
        _ = WheelPanel.shared   // build the wheel up front so the first summon is instant

        if !DragMonitor.hasAccessibility {
            DragMonitor.requestAccessibility()
        }
        if ExternalTool.ffmpeg.path == nil || ExternalTool.cwebp.path == nil {
            NSLog("DragWheel: ffmpeg or cwebp missing — video/WebP actions will explain how to install them.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DragMonitor.shared.stop()
    }
}
