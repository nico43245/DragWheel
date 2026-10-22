import AppKit
import UserNotifications

/// Native notifications with Open / Show in Finder / Undo buttons.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private let center = UNUserNotificationCenter.current()
    private let category = "dragwheel.result"

    func setUp() {
        center.delegate = self
        let open = UNNotificationAction(identifier: "open", title: "Open")
        let reveal = UNNotificationAction(identifier: "reveal", title: "Show in Finder")
        let undo = UNNotificationAction(identifier: "undo", title: "Undo", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [open, reveal, undo], intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func report(_ outcomes: [Outcome]) {
        let made = outcomes.compactMap { o -> (URL, URL)? in
            if case .success(let url?) = o.result { return (o.source, url) } else { return nil }
        }
        let failures = outcomes.compactMap { o -> String? in
            if case .failure(let e) = o.result { return "\(o.source.lastPathComponent): \(e.localizedDescription)" } else { return nil }
        }

        if let (source, output) = made.first {
            let content = UNMutableNotificationContent()
            content.categoryIdentifier = category
            if made.count == 1 {
                content.title = output.lastPathComponent
                content.body = sizeSummary(from: source, to: output)
            } else {
                content.title = "\(made.count) files ready"
                content.body = made.map { $0.1.lastPathComponent }.prefix(4).joined(separator: ", ")
            }
            if !failures.isEmpty { content.body += "\n\(failures.count) failed: \(failures[0])" }
            content.userInfo = ["paths": made.map { $0.1.path }]
            post(content)
            if Settings.shared.playSound { NSSound(named: "Glass")?.play() }
        } else if let failure = failures.first {
            showError(failures.count == 1 ? failure : "\(failures.count) files failed. \(failure)")
        }
    }

    func showError(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "DragWheel couldn't do that"
        content.body = message
        post(content)
        if Settings.shared.playSound { NSSound(named: "Funk")?.play() }
    }

    private func post(_ content: UNMutableNotificationContent) {
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// "photo.webp · 2.4 MB → 610 KB (75% smaller)"
    func sizeSummary(from source: URL, to output: URL) -> String {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: output.path, isDirectory: &isDir), isDir.boolValue {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: output.path).count) ?? 0
            return "\(count) files in \(output.lastPathComponent)"
        }
        let before = ImageOps.fileSize(source), after = ImageOps.fileSize(output)
        let f = ByteCountFormatter()
        var text = "\(f.string(fromByteCount: before)) → \(f.string(fromByteCount: after))"
        if before > 0 && after > 0 {
            let change = Int((1 - Double(after) / Double(before)) * 100)
            if change > 0 { text += " (\(change)% smaller)" } else if change < 0 { text += " (\(-change)% larger)" }
        }
        return text
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let urls = (response.notification.request.content.userInfo["paths"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            switch action {
            case "open", UNNotificationDefaultActionIdentifier:
                urls.forEach { NSWorkspace.shared.open($0) }
            case "reveal":
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            case "undo":
                // Moves to the Trash, never deletes.
                urls.forEach { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
            default: break
            }
        }
        completionHandler()
    }
}
