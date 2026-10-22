import AppKit

/// What happened to one input.
struct Outcome {
    let source: URL
    let action: ActionID
    let result: Result<URL?, Error>   // nil URL = the action opened something instead of creating a file
}

/// Routes a wheel action to the right converter and reports results.
@MainActor
final class ConversionEngine {
    static let shared = ConversionEngine()

    /// Runs `action` on `files`. Batch-friendly: independent files are processed concurrently.
    @discardableResult
    func perform(_ action: ActionID, on files: [URL], notify: Bool = true) async -> [Outcome] {
        guard !files.isEmpty else { return [] }
        let outcomes: [Outcome]

        switch action {
        case .mergePDF:
            outcomes = [await outcome(files[0], action) { try PDFOps.merge(files) }]
        case .toDOCX where files.count > 1 && files.allSatisfy({ FileKind($0) == .image }):
            outcomes = [await outcome(files[0], action) {
                let output = OutputNaming.file(for: files[0], suffix: "_images", ext: "docx")
                try await DocxWriter.imagesToDocx(files, output: output)
                return output
            }]
        case .edit, .annotate, .crop, .redact, .preview, .print:
            // Interactive: hand the files to the right app, nothing new is written.
            var list: [Outcome] = []
            for file in files { list.append(await outcome(file, action) { try await self.openInteractive(action, file); return nil }) }
            outcomes = list
        default:
            outcomes = await withTaskGroup(of: (Int, Outcome).self) { group in
                for (index, file) in files.enumerated() {
                    group.addTask { (index, await self.outcome(file, action) { try await Self.convert(action, file) }) }
                }
                var collected: [(Int, Outcome)] = []
                for await item in group { collected.append(item) }
                return collected.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }

        History.shared.record(outcomes)
        if notify { Notifier.shared.report(outcomes) }
        if Settings.shared.revealAfterConvert {
            let made = outcomes.compactMap { try? $0.result.get() }
            if !made.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(made) }
        }
        return outcomes
    }

    private func outcome(_ file: URL, _ action: ActionID, _ work: () async throws -> URL?) async -> Outcome {
        do { return Outcome(source: file, action: action, result: .success(try await work())) }
        catch { return Outcome(source: file, action: action, result: .failure(error)) }
    }

    // MARK: Routing

    /// File-producing actions. Runs off the main actor where the work is heavy.
    nonisolated private static func convert(_ action: ActionID, _ file: URL) async throws -> URL {
        let kind = FileKind(file)
        switch action {
        // Image formats — a video dropped on GIF becomes an animated GIF, a document on PDF becomes a PDF.
        case .toGIF where kind == .video: return try await MediaOps.convert(file, to: "gif")
        case .toPDF where kind == .document: return try await PDFOps.toPDF(file)
        case .toPDF where kind == .pdf: throw DragWheelError.notApplicable("\(file.lastPathComponent) is already a PDF.")
        case .toPDF:
            try requireImage(file, kind)
            let output = OutputNaming.file(for: file, ext: "pdf")
            try ImageOps.toPDF([file], output: output)
            return output
        case .toDOCX where kind == .pdf: return try PDFOps.toWord(file)
        case .toDOCX:
            try requireImage(file, kind)
            let output = OutputNaming.file(for: file, ext: "docx")
            try await DocxWriter.imagesToDocx([file], output: output)
            return output
        case .toPNG, .toWEBP, .toHEIC, .toGIF, .toAVIF, .toBMP, .toTIFF, .toJPEG:
            if kind == .pdf, let first = try? PDFOps.open(file).page(at: 0) {
                // First page of a PDF as an image.
                let temp = OutputNaming.temporaryFile(ext: "png")
                defer { try? FileManager.default.removeItem(at: temp) }
                try ImageOps.writeCGImage(try PDFOps.render(first, scale: 2), to: temp, type: .png)
                let made = try await ImageOps.convert(temp, to: imageExt(action))
                let named = OutputNaming.file(for: file, ext: imageExt(action))
                try FileManager.default.moveItem(at: made, to: named)
                return named
            }
            try requireImage(file, kind)
            return try await ImageOps.convert(file, to: imageExt(action))

        // Tools
        case .compressImage where kind == .video: return try await MediaOps.compress(file)
        case .compressImage where kind == .pdf: return try PDFOps.compress(file)
        case .compressImage: try requireImage(file, kind); return try await ImageOps.compress(file)
        case .stripMetadata: try requireImage(file, kind); return try ImageOps.stripMetadata(file)
        case .removeBackground: try requireImage(file, kind); return try VisionOps.removeBackground(file)
        case .addBackground: try requireImage(file, kind); return try ImageOps.addBackground(file)

        // Video & audio
        case .toMP4, .toMOV, .toWEBM, .videoToGIF:
            guard kind == .video else { throw DragWheelError.notApplicable("\(file.lastPathComponent) isn't a video.") }
            return try await MediaOps.convert(file, to: mediaExt(action))
        case .toMP3, .toWAV, .toM4A:
            guard kind == .video || kind == .audio else { throw DragWheelError.notApplicable("\(file.lastPathComponent) has no audio to extract.") }
            return try await MediaOps.convert(file, to: mediaExt(action))
        case .compressVideo:
            guard kind == .video else { throw DragWheelError.notApplicable("\(file.lastPathComponent) isn't a video.") }
            return try await MediaOps.compress(file)
        case .mute:
            guard kind == .video else { throw DragWheelError.notApplicable("\(file.lastPathComponent) isn't a video.") }
            return try await MediaOps.mute(file)

        // PDF & documents
        case .docToPDF:
            if kind == .image {
                let output = OutputNaming.file(for: file, ext: "pdf")
                try ImageOps.toPDF([file], output: output)
                return output
            }
            return try await PDFOps.toPDF(file)
        case .compressPDF:
            guard kind == .pdf else { throw DragWheelError.notApplicable("\(file.lastPathComponent) isn't a PDF.") }
            return try PDFOps.compress(file)
        case .splitPDF:
            guard kind == .pdf else { throw DragWheelError.notApplicable("\(file.lastPathComponent) isn't a PDF.") }
            return try PDFOps.split(file)
        case .pdfToImages:
            guard kind == .pdf else { throw DragWheelError.notApplicable("\(file.lastPathComponent) isn't a PDF.") }
            return try PDFOps.toImages(file)
        case .ocrText: return try PDFOps.ocr(file)
        case .toWord: return try PDFOps.toWord(file)

        case .mergePDF, .edit, .annotate, .crop, .redact, .preview, .print:
            throw DragWheelError.message("Internal routing error for \(action.rawValue).")
        }
    }

    private func openInteractive(_ action: ActionID, _ file: URL) async throws {
        switch action {
        case .print:
            try PDFOps.print(file)
        case .preview:
            NSWorkspace.shared.open(file)
        default:
            // Edit, annotate, crop and redact all live in Preview's Markup toolbar.
            let kind = FileKind(file)
            guard kind == .image || kind == .pdf else {
                throw DragWheelError.notApplicable("Preview can only edit images and PDFs.")
            }
            guard let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") else {
                NSWorkspace.shared.open(file); return
            }
            _ = try await NSWorkspace.shared.open([file], withApplicationAt: preview, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    nonisolated private static func requireImage(_ file: URL, _ kind: FileKind) throws {
        guard kind == .image else { throw DragWheelError.notApplicable("\(file.lastPathComponent) isn't an image.") }
    }

    nonisolated private static func imageExt(_ action: ActionID) -> String {
        switch action {
        case .toPNG: return "png"
        case .toWEBP: return "webp"
        case .toHEIC: return "heic"
        case .toGIF: return "gif"
        case .toAVIF: return "avif"
        case .toBMP: return "bmp"
        case .toTIFF: return "tiff"
        default: return "jpg"
        }
    }

    nonisolated private static func mediaExt(_ action: ActionID) -> String {
        switch action {
        case .toMP4: return "mp4"
        case .toMOV: return "mov"
        case .toWEBM: return "webm"
        case .videoToGIF: return "gif"
        case .toMP3: return "mp3"
        case .toWAV: return "wav"
        default: return "m4a"
        }
    }

    // MARK: Clipboard

    /// Saves the image on the clipboard to ~/Downloads in the chosen format.
    func convertClipboard(to action: ActionID) async {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Notifier.shared.showError("There's no image on the clipboard.")
            return
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let source = downloads.appendingPathComponent("Clipboard \(stamp).png")
        do {
            try png.write(to: source)
            if action == .toPNG {
                let outcome = Outcome(source: source, action: action, result: .success(source))
                History.shared.record([outcome]); Notifier.shared.report([outcome])
                return
            }
            await perform(action, on: [source])
            try? FileManager.default.trashItem(at: source, resultingItemURL: nil)
        } catch {
            Notifier.shared.showError(error.localizedDescription)
        }
    }
}
