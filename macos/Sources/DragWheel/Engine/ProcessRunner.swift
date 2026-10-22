import Foundation

enum DragWheelError: LocalizedError {
    case message(String)
    case missingTool(String, install: String)
    case notApplicable(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .missingTool(let tool, let install): return "\(tool) is not installed. Install it with: \(install)"
        case .notApplicable(let m): return m
        }
    }
}

/// Finds the command-line helpers we rely on (Homebrew first).
enum ExternalTool: String {
    case ffmpeg, cwebp

    var installHint: String { "brew install \(self == .ffmpeg ? "ffmpeg" : "webp")" }

    var path: String? {
        ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
            .map { "\($0)/\(rawValue)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func require() throws -> String {
        guard let path else { throw DragWheelError.missingTool(rawValue, install: installHint) }
        return path
    }
}

enum ProcessRunner {
    /// Runs an executable with an argument list (never through a shell) and waits for it.
    /// Throws with the tool's stderr when it exits non-zero.
    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = directory }
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            // Drain stderr while the tool runs so a chatty tool can't fill the pipe and stall.
            var data = Data()
            let drained = DispatchGroup()
            drained.enter()
            DispatchQueue.global(qos: .utility).async {
                data = errors.fileHandleForReading.readDataToEndOfFile()
                drained.leave()
            }
            process.terminationHandler = { p in
                drained.wait()
                if p.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: "\n").suffix(3).joined(separator: "\n") ?? ""
                    let name = URL(fileURLWithPath: executable).lastPathComponent
                    continuation.resume(throwing: DragWheelError.message("\(name) failed (\(p.terminationStatus)): \(text)"))
                }
            }
            do {
                try process.run()
            } catch {
                try? errors.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
    }

    static func ffmpeg(_ arguments: [String]) async throws {
        let path = try ExternalTool.ffmpeg.require()
        try await run(path, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"] + arguments)
    }
}

/// Picks output paths that never overwrite anything: photo.webp, photo_1.webp, photo_2.webp …
enum OutputNaming {
    static func file(for source: URL, suffix: String = "", ext: String) -> URL {
        let folder = Settings.shared.outputFolder(for: source)
        let base = source.deletingPathExtension().lastPathComponent + suffix
        return unique(in: folder, base: base, ext: ext, avoiding: source)
    }

    static func folder(for source: URL, suffix: String) -> URL {
        let parent = Settings.shared.outputFolder(for: source)
        let base = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(base)_\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    static func unique(in folder: URL, base: String, ext: String, avoiding source: URL? = nil) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) || candidate.path == source?.path {
            candidate = folder.appendingPathComponent("\(base)_\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    static func temporaryFile(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dragwheel-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }
}
