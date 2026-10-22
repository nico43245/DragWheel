import Foundation

/// Video and audio through Homebrew's ffmpeg.
enum MediaOps {
    static func convert(_ input: URL, to ext: String) async throws -> URL {
        let output = OutputNaming.file(for: input, ext: ext)
        let crf = Settings.shared.quality >= 85 ? "20" : Settings.shared.quality >= 60 ? "23" : "28"
        var args = ["-i", input.path]
        switch ext {
        case "mp4":
            args += ["-c:v", "libx264", "-crf", crf, "-preset", "medium", "-pix_fmt", "yuv420p",
                     "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"]
        case "mov":
            args += ["-c:v", "libx264", "-crf", crf, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k"]
        case "webm":
            args += ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1", "-c:a", "libopus"]
        case "mp3":
            args += ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case "wav":
            args += ["-vn", "-c:a", "pcm_s16le"]
        case "m4a":
            args += ["-vn", "-c:a", "aac", "-b:a", "192k"]
        case "gif":
            args += ["-vf", "fps=12,scale='min(640,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
                     "-loop", "0"]
        default:
            throw DragWheelError.message("Unsupported media format: \(ext)")
        }
        try await run(args, output)
        return output
    }

    static func compress(_ input: URL) async throws -> URL {
        let output = OutputNaming.file(for: input, suffix: "_compressed", ext: "mp4")
        try await run(["-i", input.path, "-c:v", "libx264", "-crf", "28", "-preset", "slow", "-pix_fmt", "yuv420p",
                       "-vf", "scale='min(1920,iw)':-2", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"], output)
        if ImageOps.fileSize(output) >= ImageOps.fileSize(input) {
            try? FileManager.default.removeItem(at: output)
            throw DragWheelError.message("\(input.lastPathComponent) is already well compressed.")
        }
        return output
    }

    static func mute(_ input: URL) async throws -> URL {
        let ext = input.pathExtension.isEmpty ? "mp4" : input.pathExtension.lowercased()
        let output = OutputNaming.file(for: input, suffix: "_muted", ext: ext)
        try await run(["-i", input.path, "-map", "0", "-map", "-0:a", "-c", "copy"], output)
        return output
    }

    private static func run(_ args: [String], _ output: URL) async throws {
        do {
            try await ProcessRunner.ffmpeg(args + [output.path])
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
