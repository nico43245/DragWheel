import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Image conversion and editing, done in-process with ImageIO where macOS can,
/// and with Homebrew's cwebp for WebP.
enum ImageOps {
    static func loadCGImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw DragWheelError.message("Can't read \(url.lastPathComponent) as an image.") }
        return image
    }

    /// Converts to any format ImageIO can write (png, jpeg, heic, avif, gif, bmp, tiff).
    /// Multi-frame sources (animated GIF, multi-page TIFF) keep their frames when the target supports it.
    static func convert(_ input: URL, to ext: String) async throws -> URL {
        if ext == "webp" { return try await toWebP(input, suffix: "") }
        let output = OutputNaming.file(for: input, ext: ext)
        do {
            try write(input, to: output, type: try utType(for: ext), quality: Settings.shared.qualityFraction, keepMetadata: true)
        } catch where ext == "avif" && ExternalTool.ffmpeg.path != nil {
            // Some Macs (older hardware, virtual machines) can read AVIF but not write it.
            try await avifWithFFmpeg(input, to: output)
        }
        return output
    }

    private static func avifWithFFmpeg(_ input: URL, to output: URL) async throws {
        let crf = String(Int(63 - Settings.shared.quality * 0.45))   // quality 80 → crf 27
        do {
            try await ProcessRunner.ffmpeg(["-i", input.path, "-frames:v", "1",
                                            "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
                                            "-c:v", "libsvtav1", "-crf", crf, output.path])
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    static func utType(for ext: String) throws -> UTType {
        switch ext {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "avif": return UTType("public.avif") ?? .heic
        case "gif": return .gif
        case "bmp": return .bmp
        case "tiff", "tif": return .tiff
        default: throw DragWheelError.message("Unsupported image format: \(ext)")
        }
    }

    static func write(_ input: URL, to output: URL, type: UTType, quality: Double, keepMetadata: Bool) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw DragWheelError.message("Can't read \(input.lastPathComponent) as an image.")
        }
        let frames = CGImageSourceGetCount(source)
        let multiFrame = [UTType.gif, .tiff].contains(type) ? frames : min(frames, 1)
        guard multiFrame > 0,
              let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, multiFrame, nil)
        else { throw DragWheelError.message("macOS can't write \(type.preferredFilenameExtension ?? "this format").") }

        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if !keepMetadata {
            options[kCGImageMetadataShouldExcludeGPS] = true
            options[kCGImageMetadataShouldExcludeXMP] = true
        }
        for index in 0..<multiFrame {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            var frameOptions = options
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            if keepMetadata {
                frameOptions.merge(props) { mine, _ in mine }
            } else if let orientation = props[kCGImagePropertyOrientation] {
                // Keep only what's needed to display the picture the right way up.
                frameOptions[kCGImagePropertyOrientation] = orientation
            }
            if type == .gif, let gif = props[kCGImagePropertyGIFDictionary] {
                frameOptions[kCGImagePropertyGIFDictionary] = gif
            }
            CGImageDestinationAddImage(dest, frame, frameOptions as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: output)
            throw DragWheelError.message("Writing \(output.lastPathComponent) failed.")
        }
    }

    static func toWebP(_ input: URL, suffix: String) async throws -> URL {
        let cwebp = try ExternalTool.cwebp.require()
        let output = OutputNaming.file(for: input, suffix: suffix, ext: "webp")
        // cwebp reads PNG/JPEG/TIFF/WebP; hand it a PNG for anything else (HEIC, AVIF, GIF…).
        var feed = input
        var temp: URL?
        if !["png", "jpg", "jpeg", "tif", "tiff", "webp"].contains(input.pathExtension.lowercased()) {
            let png = OutputNaming.temporaryFile(ext: "png")
            try write(input, to: png, type: .png, quality: 1, keepMetadata: false)
            feed = png
            temp = png
        }
        defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
        try await ProcessRunner.run(cwebp, ["-quiet", "-q", "\(Int(Settings.shared.quality))", "-metadata", "icc", feed.path, "-o", output.path])
        return output
    }

    // MARK: Tools

    /// Re-encodes lossy formats at the chosen quality; images with transparency go to WebP,
    /// opaque ones to JPEG. Keeps the result only if it's actually smaller.
    static func compress(_ input: URL) async throws -> URL {
        let ext = input.pathExtension.lowercased()
        let output: URL
        if ["jpg", "jpeg", "heic", "avif"].contains(ext) {
            output = OutputNaming.file(for: input, suffix: "_compressed", ext: ext == "jpg" ? "jpg" : ext)
            try write(input, to: output, type: try utType(for: ext), quality: min(Settings.shared.qualityFraction, 0.75), keepMetadata: true)
        } else if try ext == "webp" || hasAlpha(loadCGImage(input)) {
            output = try await toWebP(input, suffix: "_compressed")
        } else {
            output = OutputNaming.file(for: input, suffix: "_compressed", ext: "jpg")
            try write(input, to: output, type: .jpeg, quality: min(Settings.shared.qualityFraction, 0.75), keepMetadata: true)
        }
        if fileSize(output) >= fileSize(input) {
            try? FileManager.default.removeItem(at: output)
            throw DragWheelError.message("\(input.lastPathComponent) is already as small as it gets.")
        }
        return output
    }

    static func stripMetadata(_ input: URL) throws -> URL {
        let ext = input.pathExtension.lowercased()
        let known = try? utType(for: ext)
        let type = known ?? .png
        let output = OutputNaming.file(for: input, suffix: "_clean", ext: known == nil ? "png" : ext)
        try write(input, to: output, type: type, quality: 0.95, keepMetadata: false)
        return output
    }

    /// Flattens transparency onto white.
    static func addBackground(_ input: URL, color: NSColor = .white) throws -> URL {
        let image = try loadCGImage(input)
        let ctx = try bitmapContext(width: image.width, height: image.height, opaque: true)
        ctx.setFillColor(color.usingColorSpace(.sRGB)?.cgColor ?? CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = ctx.makeImage() else { throw DragWheelError.message("Couldn't draw the image.") }
        let output = OutputNaming.file(for: input, suffix: "_bg", ext: "png")
        try writeCGImage(flat, to: output, type: .png)
        return output
    }

    /// A one-page PDF sized to the image.
    static func toPDF(_ inputs: [URL], output: URL) throws {
        var box = CGRect.zero
        guard let ctx = CGContext(output as CFURL, mediaBox: &box, nil) else {
            throw DragWheelError.message("Couldn't create \(output.lastPathComponent).")
        }
        for input in inputs {
            let image = try loadCGImage(input)
            var page = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            ctx.beginPage(mediaBox: &page)
            ctx.draw(image, in: page)
            ctx.endPage()
        }
        ctx.closePDF()
    }

    // MARK: Helpers

    static func hasAlpha(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: return true
        }
    }

    static func bitmapContext(width: Int, height: Int, opaque: Bool = false) throws -> CGContext {
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: alpha.rawValue)
        else { throw DragWheelError.message("Image too large.") }
        return ctx
    }

    static func writeCGImage(_ image: CGImage, to output: URL, type: UTType, quality: Double = 1) throws {
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw DragWheelError.message("Couldn't create \(output.lastPathComponent).")
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw DragWheelError.message("Writing \(output.lastPathComponent) failed.") }
    }

    static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
