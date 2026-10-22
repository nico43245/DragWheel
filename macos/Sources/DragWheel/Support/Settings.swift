import AppKit
import Combine
import ServiceManagement

/// Where converted files are written.
enum OutputLocation: String, CaseIterable, Identifiable {
    case nextToSource
    case customFolder

    var id: String { rawValue }
    var title: String {
        switch self {
        case .nextToSource: return "Next to the original file"
        case .customFolder: return "A folder I choose"
        }
    }
}

/// User preferences, persisted in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var outputLocation: OutputLocation {
        didSet { defaults.set(outputLocation.rawValue, forKey: "outputLocation") }
    }
    @Published var customFolderPath: String {
        didSet { defaults.set(customFolderPath, forKey: "customFolderPath") }
    }
    /// Lossy quality, 20...100.
    @Published var quality: Double {
        didSet { defaults.set(quality, forKey: "quality") }
    }
    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }
    @Published var revealAfterConvert: Bool {
        didSet { defaults.set(revealAfterConvert, forKey: "revealAfterConvert") }
    }
    @Published var themeID: String {
        didSet { defaults.set(themeID, forKey: "themeID") }
    }

    private init() {
        defaults.register(defaults: [
            "outputLocation": OutputLocation.nextToSource.rawValue,
            "customFolderPath": NSHomeDirectory() + "/Downloads",
            "quality": 80.0,
            "playSound": true,
            "revealAfterConvert": false,
            "themeID": Theme.all[0].id,
        ])
        outputLocation = OutputLocation(rawValue: defaults.string(forKey: "outputLocation") ?? "") ?? .nextToSource
        customFolderPath = defaults.string(forKey: "customFolderPath") ?? NSHomeDirectory()
        quality = defaults.double(forKey: "quality")
        playSound = defaults.bool(forKey: "playSound")
        revealAfterConvert = defaults.bool(forKey: "revealAfterConvert")
        themeID = defaults.string(forKey: "themeID") ?? Theme.all[0].id
    }

    var theme: Theme { Theme.all.first { $0.id == themeID } ?? Theme.all[0] }

    /// 0...1 for ImageIO.
    var qualityFraction: Double { quality / 100 }

    func outputFolder(for source: URL) -> URL {
        switch outputLocation {
        case .nextToSource:
            return source.deletingLastPathComponent()
        case .customFolder:
            let folder = URL(fileURLWithPath: customFolderPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("DragWheel: launch at login change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }
}
