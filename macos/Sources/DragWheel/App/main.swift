import AppKit
import SwiftUI

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let args = CommandLine.arguments

    // Scriptable mode: DragWheel --run <action> <file>…  (prints each result, then exits)
    if args.count >= 4, args[1] == "--run" {
        guard let action = ActionID(rawValue: args[2]) else {
            print("Unknown action '\(args[2])'. Actions: \(ActionID.allCases.map(\.rawValue).joined(separator: " "))")
            exit(2)
        }
        let files = args.dropFirst(3).map { URL(fileURLWithPath: $0).standardizedFileURL }
        Task { @MainActor in
            var failed = false
            for outcome in await ConversionEngine.shared.perform(action, on: files, notify: false) {
                switch outcome.result {
                case .success(let url): print("✓ \(outcome.source.lastPathComponent) → \(url?.path ?? "(opened)")")
                case .failure(let error): failed = true; print("✗ \(outcome.source.lastPathComponent): \(error.localizedDescription)")
                }
            }
            exit(failed ? 1 : 0)
        }
        app.run()
    }

    // Design check: DragWheel --snapshot <out.png> [page] [hovered petal 0-8] [theme id]
    if args.count >= 3, args[1] == "--snapshot" {
        let state = WheelState.shared
        state.pageIndex = args.count > 3 ? Int(args[3]) ?? 0 : 0
        state.hovered = args.count > 4 ? Int(args[4]) : nil
        let saved = Settings.shared.themeID
        if args.count > 5 { Settings.shared.themeID = args[5] }
        let renderer = ImageRenderer(content: WheelView(state: state, showsBlur: false))
        renderer.scale = 2
        guard let image = renderer.cgImage else { exit(1) }
        try? ImageOps.writeCGImage(image, to: URL(fileURLWithPath: args[2]), type: .png)
        Settings.shared.themeID = saved
        exit(0)
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
