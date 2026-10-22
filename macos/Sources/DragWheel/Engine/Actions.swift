import Foundation
import UniformTypeIdentifiers

/// Everything the wheel or the converter window can do to a file.
enum ActionID: String, CaseIterable {
    // Image formats
    case toPNG, toWEBP, toHEIC, toGIF, toAVIF, toBMP, toPDF, toDOCX, toTIFF, toJPEG
    // Tools & edit
    case compressImage, stripMetadata, edit, annotate, removeBackground, preview, crop, redact, addBackground
    // Video & audio
    case toMP4, videoToGIF, toMP3, toWAV, toMOV, toWEBM, toM4A, compressVideo, mute
    // PDF & documents
    case docToPDF, compressPDF, splitPDF, mergePDF, ocrText, pdfToImages, toWord, print
}

struct WheelAction: Identifiable {
    let id: ActionID
    let title: String
    let hint: String
    let symbol: String
}

/// One ring of the wheel: eight petals around a center button.
struct WheelPage: Identifiable {
    let id: Int
    let title: String
    let petals: [WheelAction]
    let center: WheelAction

    var all: [WheelAction] { petals + [center] }
}

enum Catalog {
    static let pages: [WheelPage] = [
        WheelPage(id: 0, title: "IMAGE FORMATS", petals: [
            WheelAction(id: .toPNG, title: "PNG", hint: "Lossless · transparency", symbol: "photo"),
            WheelAction(id: .toWEBP, title: "WEBP", hint: "Smallest for the web", symbol: "globe"),
            WheelAction(id: .toHEIC, title: "HEIC", hint: "iPhone format", symbol: "iphone"),
            WheelAction(id: .toGIF, title: "GIF", hint: "Web · animation", symbol: "play.square"),
            WheelAction(id: .toAVIF, title: "AVIF", hint: "Next-gen, tiny", symbol: "sparkle"),
            WheelAction(id: .toJPEG, title: "JPEG", hint: "Universal photo", symbol: "camera"),
            WheelAction(id: .toPDF, title: "PDF", hint: "Document page", symbol: "doc.richtext"),
            WheelAction(id: .toDOCX, title: "DOCX", hint: "Image in a Word file", symbol: "doc.text"),
        ], center: WheelAction(id: .toTIFF, title: "TIFF", hint: "Print · archival", symbol: "printer")),

        WheelPage(id: 1, title: "TOOLS & EDIT", petals: [
            WheelAction(id: .compressImage, title: "COMPRESS", hint: "Shrink file size", symbol: "arrow.down.forward.and.arrow.up.backward"),
            WheelAction(id: .stripMetadata, title: "METADATA", hint: "Strip GPS & EXIF", symbol: "tag.slash"),
            WheelAction(id: .edit, title: "EDIT", hint: "Light · colour · rotate", symbol: "slider.horizontal.3"),
            WheelAction(id: .annotate, title: "ANNOTATE", hint: "Arrows · text · shapes", symbol: "pencil.tip.crop.circle"),
            WheelAction(id: .removeBackground, title: "REMOVE BG", hint: "Cut out the subject", symbol: "wand.and.stars"),
            WheelAction(id: .preview, title: "PREVIEW", hint: "Quick look", symbol: "eye"),
            WheelAction(id: .crop, title: "CROP", hint: "Trim in Preview", symbol: "crop"),
            WheelAction(id: .redact, title: "REDACT", hint: "Hide sensitive info", symbol: "eye.slash"),
        ], center: WheelAction(id: .addBackground, title: "ADD BG", hint: "Fill transparency white", symbol: "square.fill")),

        WheelPage(id: 2, title: "VIDEO & AUDIO", petals: [
            WheelAction(id: .toMP4, title: "MP4", hint: "Universal video", symbol: "video"),
            WheelAction(id: .videoToGIF, title: "GIF", hint: "Clip to GIF", symbol: "play.square.stack"),
            WheelAction(id: .toMP3, title: "MP3", hint: "Extract sound", symbol: "music.note"),
            WheelAction(id: .toWAV, title: "WAV", hint: "Lossless audio", symbol: "waveform"),
            WheelAction(id: .toMOV, title: "MOV", hint: "QuickTime video", symbol: "film"),
            WheelAction(id: .toWEBM, title: "WEBM", hint: "HTML5 video", symbol: "play.rectangle"),
            WheelAction(id: .toM4A, title: "M4A", hint: "Apple audio", symbol: "headphones"),
            WheelAction(id: .compressVideo, title: "COMPRESS", hint: "Reduce bitrate", symbol: "arrow.down.right.and.arrow.up.left"),
        ], center: WheelAction(id: .mute, title: "MUTE", hint: "Strip the audio track", symbol: "speaker.slash")),

        WheelPage(id: 3, title: "PDF & DOCUMENTS", petals: [
            WheelAction(id: .docToPDF, title: "TO PDF", hint: "Export to PDF", symbol: "doc.text"),
            WheelAction(id: .compressPDF, title: "COMPRESS", hint: "Shrink PDF size", symbol: "arrow.down.circle"),
            WheelAction(id: .splitPDF, title: "SPLIT", hint: "One PDF per page", symbol: "scissors"),
            WheelAction(id: .mergePDF, title: "MERGE", hint: "Combine into one", symbol: "doc.on.doc"),
            WheelAction(id: .ocrText, title: "OCR TEXT", hint: "Recognize text", symbol: "text.viewfinder"),
            WheelAction(id: .pdfToImages, title: "TO IMAGES", hint: "Page by page PNG", symbol: "photo.stack"),
            WheelAction(id: .toWord, title: "TO WORD", hint: "Editable DOCX", symbol: "doc.richtext"),
            WheelAction(id: .print, title: "PRINT", hint: "Send to printer", symbol: "printer"),
        ], center: WheelAction(id: .preview, title: "PREVIEW", hint: "View document", symbol: "eye")),
    ]

    static func action(_ id: ActionID) -> WheelAction {
        for page in pages { if let a = page.all.first(where: { $0.id == id }) { return a } }
        return WheelAction(id: id, title: id.rawValue.uppercased(), hint: "", symbol: "questionmark")
    }

    /// The page that fits the dragged files best.
    static func bestPage(for files: [URL]) -> Int {
        guard let first = files.first else { return 0 }
        switch FileKind(first) {
        case .image: return 0
        case .video, .audio: return 2
        case .pdf, .document: return 3
        case .other: return 0
        }
    }
}

/// Coarse classification of an input file.
enum FileKind {
    case image, video, audio, pdf, document, other

    init(_ url: URL) {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        guard let type else { self = .other; return }
        if type.conforms(to: .pdf) { self = .pdf }
        else if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .movie) || type.conforms(to: .video) { self = .video }
        else if type.conforms(to: .audio) { self = .audio }
        else if type.conforms(to: .text) || type.conforms(to: .rtf) || type.conforms(to: .html)
                    || ["doc", "docx", "odt", "rtfd", "pages", "md", "webarchive"].contains(url.pathExtension.lowercased()) {
            self = .document
        } else { self = .other }
    }
}
