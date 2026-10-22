import AppKit
import PDFKit

/// PDF and document work with PDFKit, Vision and AppKit's text system.
enum PDFOps {
    static func open(_ url: URL) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw DragWheelError.message("Can't open \(url.lastPathComponent) as a PDF.") }
        if doc.isLocked { throw DragWheelError.message("\(url.lastPathComponent) is password protected.") }
        return doc
    }

    /// Images → one PDF page each; text/RTF/Word/HTML → paginated A4 PDF.
    @MainActor
    static func toPDF(_ input: URL) throws -> URL {
        let output = OutputNaming.file(for: input, ext: "pdf")
        switch FileKind(input) {
        case .image:
            try ImageOps.toPDF([input], output: output)
        case .document:
            try renderDocument(input, to: output)
        case .pdf:
            throw DragWheelError.notApplicable("\(input.lastPathComponent) is already a PDF.")
        default:
            throw DragWheelError.notApplicable("Can't turn \(input.lastPathComponent) into a PDF.")
        }
        return output
    }

    @MainActor
    private static func renderDocument(_ input: URL, to output: URL) throws {
        let text = try NSAttributedString(url: input, options: [:], documentAttributes: nil)
        let page = NSSize(width: 595, height: 842) // A4 in points
        let margin: CGFloat = 56
        // Start one point tall and grow to the text, so short documents don't spill onto a blank page.
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: page.width - 2 * margin, height: 1))
        view.minSize = .zero
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()

        let info = NSPrintInfo()
        info.paperSize = page
        info.topMargin = margin; info.bottomMargin = margin
        info.leftMargin = margin; info.rightMargin = margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run(), FileManager.default.fileExists(atPath: output.path) else {
            throw DragWheelError.message("Couldn't render \(input.lastPathComponent) to PDF.")
        }
    }

    /// Re-saves with images downsampled and JPEG-encoded; keeps text selectable.
    static func compress(_ input: URL) throws -> URL {
        let doc = try open(input)
        let output = OutputNaming.file(for: input, suffix: "_compressed", ext: "pdf")
        let ok = doc.write(to: output, withOptions: [
            .saveImagesAsJPEGOption: true,
            .optimizeImagesForScreenOption: true,
        ])
        guard ok else { throw DragWheelError.message("Couldn't write \(output.lastPathComponent).") }
        if ImageOps.fileSize(output) >= ImageOps.fileSize(input) {
            try? FileManager.default.removeItem(at: output)
            throw DragWheelError.message("\(input.lastPathComponent) is already as small as it gets.")
        }
        return output
    }

    /// One PDF per page, in a new folder next to the original.
    static func split(_ input: URL) throws -> URL {
        let doc = try open(input)
        guard doc.pageCount > 1 else { throw DragWheelError.notApplicable("\(input.lastPathComponent) has only one page.") }
        let folder = OutputNaming.folder(for: input, suffix: "_pages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = input.deletingPathExtension().lastPathComponent
        let digits = String(doc.pageCount).count
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let number = String(repeating: "0", count: digits - String(i + 1).count) + String(i + 1)
            single.write(to: folder.appendingPathComponent("\(base)_p\(number).pdf"))
        }
        return folder
    }

    /// Combines PDFs and images (in the order given) into one PDF.
    static func merge(_ inputs: [URL]) throws -> URL {
        guard inputs.count > 1 else { throw DragWheelError.notApplicable("Drop two or more files to merge them.") }
        let merged = PDFDocument()
        for url in inputs {
            switch FileKind(url) {
            case .pdf:
                let doc = try open(url)
                for i in 0..<doc.pageCount {
                    if let page = doc.page(at: i)?.copy() as? PDFPage { merged.insert(page, at: merged.pageCount) }
                }
            case .image:
                if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                    merged.insert(page, at: merged.pageCount)
                }
            default:
                throw DragWheelError.notApplicable("\(url.lastPathComponent) can't be merged into a PDF.")
            }
        }
        let folder = Settings.shared.outputFolder(for: inputs[0])
        let output = OutputNaming.unique(in: folder, base: "Merged", ext: "pdf")
        guard merged.write(to: output) else { throw DragWheelError.message("Couldn't write \(output.lastPathComponent).") }
        return output
    }

    /// Every page as a PNG at 2× (144 dpi), in a new folder.
    static func toImages(_ input: URL) throws -> URL {
        let doc = try open(input)
        let folder = OutputNaming.folder(for: input, suffix: "_images")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = input.deletingPathExtension().lastPathComponent
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let image = try render(page, scale: 2)
            try ImageOps.writeCGImage(image, to: folder.appendingPathComponent("\(base)_p\(i + 1).png"), type: .png)
        }
        return folder
    }

    /// Text from images or PDFs. Uses the PDF's own text layer when it has one, OCR otherwise.
    static func ocr(_ input: URL) throws -> URL {
        let text = try extractText(input, forceOCR: FileKind(input) == .image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DragWheelError.message("No text found in \(input.lastPathComponent).")
        }
        let output = OutputNaming.file(for: input, suffix: "_text", ext: "txt")
        try text.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    /// PDF (or image) → editable Word document.
    static func toWord(_ input: URL) throws -> URL {
        let output = OutputNaming.file(for: input, ext: "docx")
        let body: NSAttributedString
        if FileKind(input) == .pdf, let rich = textLayer(of: input),
           !rich.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body = rich
        } else {
            let text = try extractText(input, forceOCR: true)
            body = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        }
        let data = try body.data(from: NSRange(location: 0, length: body.length),
                                 documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        try data.write(to: output)
        return output
    }

    @MainActor
    static func print(_ input: URL) throws {
        let doc: PDFDocument
        switch FileKind(input) {
        case .pdf:
            doc = try open(input)
        case .image:
            guard let image = NSImage(contentsOf: input), let page = PDFPage(image: image) else {
                throw DragWheelError.message("Can't read \(input.lastPathComponent).")
            }
            doc = PDFDocument()
            doc.insert(page, at: 0)
        default:
            throw DragWheelError.notApplicable("Printing works for PDFs and images.")
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let op = doc.printOperation(for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true) else {
            throw DragWheelError.message("Couldn't prepare \(input.lastPathComponent) for printing.")
        }
        op.showsPrintPanel = true
        op.run()
    }

    // MARK: Helpers

    /// The PDF's own text with its fonts, pages separated by a page break.
    static func textLayer(of url: URL) -> NSAttributedString? {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { return nil }
        let combined = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.attributedString else { continue }
            if combined.length > 0 { combined.append(NSAttributedString(string: "\u{0C}")) }
            combined.append(page)
        }
        return combined
    }

    static func extractText(_ input: URL, forceOCR: Bool) throws -> String {
        switch FileKind(input) {
        case .image:
            return try VisionOps.recognizeText(in: ImageOps.loadCGImage(input))
        case .pdf:
            let doc = try open(input)
            var pages: [String] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                let own = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !own.isEmpty && !forceOCR {
                    pages.append(own)
                } else {
                    pages.append(try VisionOps.recognizeText(in: render(page, scale: 2)))
                }
            }
            return pages.joined(separator: "\n\n")
        default:
            throw DragWheelError.notApplicable("Text recognition works for images and PDFs.")
        }
    }

    static func render(_ page: PDFPage, scale: CGFloat) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = page.rotation % 180 != 0
        let size = CGSize(width: (rotated ? bounds.height : bounds.width) * scale,
                          height: (rotated ? bounds.width : bounds.height) * scale)
        let ctx = try ImageOps.bitmapContext(width: Int(size.width), height: Int(size.height))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        guard let image = ctx.makeImage() else { throw DragWheelError.message("Couldn't render page.") }
        return image
    }
}
