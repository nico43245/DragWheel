namespace DragWheel.Core;

/// <summary>Everything the wheel or the converter window can do. Names match the macOS app.</summary>
public enum ActionId
{
    // Image formats
    toPNG, toWEBP, toHEIC, toGIF, toAVIF, toBMP, toPDF, toDOCX, toTIFF, toJPEG,
    // Tools & edit
    compressImage, stripMetadata, edit, annotate, removeBackground, preview, crop, redact, addBackground,
    // Video & audio
    toMP4, videoToGIF, toMP3, toWAV, toMOV, toWEBM, toM4A, compressVideo, mute,
    // PDF & documents
    docToPDF, compressPDF, splitPDF, mergePDF, ocrText, pdfToImages, toWord, print,
}

/// <param name="Glyph">A Segoe Fluent Icons / Segoe MDL2 Assets code point.</param>
public sealed record WheelAction(ActionId Id, string Title, string Hint, string Glyph);

/// <summary>One ring of the wheel: eight petals around a center button.</summary>
public sealed record WheelPage(int Index, string Title, IReadOnlyList<WheelAction> Petals, WheelAction Center)
{
    public IEnumerable<WheelAction> All => Petals.Append(Center);
}

public static class Catalog
{
    public static readonly IReadOnlyList<WheelPage> Pages =
    [
        new(0, "IMAGE FORMATS",
        [
            new(ActionId.toPNG, "PNG", "Lossless · transparency", ""),
            new(ActionId.toWEBP, "WEBP", "Smallest for the web", ""),
            new(ActionId.toHEIC, "HEIC", "iPhone format", ""),
            new(ActionId.toGIF, "GIF", "Web · animation", ""),
            new(ActionId.toAVIF, "AVIF", "Next-gen, tiny", ""),
            new(ActionId.toJPEG, "JPEG", "Universal photo", ""),
            new(ActionId.toPDF, "PDF", "Document page", ""),
            new(ActionId.toDOCX, "DOCX", "Image in a Word file", ""),
        ], new(ActionId.toTIFF, "TIFF", "Print · archival", "")),

        new(1, "TOOLS & EDIT",
        [
            new(ActionId.compressImage, "COMPRESS", "Shrink file size", ""),
            new(ActionId.stripMetadata, "METADATA", "Strip GPS & EXIF", ""),
            new(ActionId.edit, "EDIT", "Light · colour · rotate", ""),
            new(ActionId.annotate, "ANNOTATE", "Arrows · text · shapes", ""),
            new(ActionId.removeBackground, "REMOVE BG", "Cut out the subject", ""),
            new(ActionId.preview, "PREVIEW", "Quick look", ""),
            new(ActionId.crop, "CROP", "Trim in the editor", ""),
            new(ActionId.redact, "REDACT", "Hide sensitive info", ""),
        ], new(ActionId.addBackground, "ADD BG", "Fill transparency white", "")),

        new(2, "VIDEO & AUDIO",
        [
            new(ActionId.toMP4, "MP4", "Universal video", ""),
            new(ActionId.videoToGIF, "GIF", "Clip to GIF", ""),
            new(ActionId.toMP3, "MP3", "Extract sound", ""),
            new(ActionId.toWAV, "WAV", "Lossless audio", ""),
            new(ActionId.toMOV, "MOV", "QuickTime video", ""),
            new(ActionId.toWEBM, "WEBM", "HTML5 video", ""),
            new(ActionId.toM4A, "M4A", "Apple audio", ""),
            new(ActionId.compressVideo, "COMPRESS", "Reduce bitrate", ""),
        ], new(ActionId.mute, "MUTE", "Strip the audio track", "")),

        new(3, "PDF & DOCUMENTS",
        [
            new(ActionId.docToPDF, "TO PDF", "Export to PDF", ""),
            new(ActionId.compressPDF, "COMPRESS", "Shrink PDF size", ""),
            new(ActionId.splitPDF, "SPLIT", "One PDF per page", ""),
            new(ActionId.mergePDF, "MERGE", "Combine into one", ""),
            new(ActionId.ocrText, "OCR TEXT", "Recognize text", ""),
            new(ActionId.pdfToImages, "TO IMAGES", "Page by page PNG", ""),
            new(ActionId.toWord, "TO WORD", "Editable DOCX", ""),
            new(ActionId.print, "PRINT", "Send to printer", ""),
        ], new(ActionId.preview, "PREVIEW", "View document", "")),
    ];

    /// <summary>Extra formats offered in the converter window only.</summary>
    public static readonly WheelAction Bmp = new(ActionId.toBMP, "BMP", "Uncompressed bitmap", "");

    public static WheelAction Action(ActionId id) =>
        Pages.SelectMany(p => p.All).FirstOrDefault(a => a.Id == id)
        ?? (id == ActionId.toBMP ? Bmp : new WheelAction(id, id.ToString().ToUpperInvariant(), "", ""));

    /// <summary>The page that fits the dragged files best.</summary>
    public static int BestPage(IReadOnlyList<string> files)
    {
        if (files.Count == 0) return 0;
        return FileKinds.Of(files[0]) switch
        {
            FileKind.Video or FileKind.Audio => 2,
            FileKind.Pdf or FileKind.Document => 3,
            _ => 0,
        };
    }
}

public enum FileKind { Image, Video, Audio, Pdf, Document, Other }

public static class FileKinds
{
    private static readonly HashSet<string> Images = Set("png jpg jpeg jpe jfif heic heif avif webp gif bmp tif tiff ico jxl psd tga");
    private static readonly HashSet<string> Videos = Set("mp4 mov m4v mkv webm avi wmv flv mpg mpeg 3gp ts mts");
    private static readonly HashSet<string> Audio = Set("mp3 wav m4a aac flac ogg opus wma aiff aif");
    private static readonly HashSet<string> Documents = Set("txt md rtf html htm docx odt csv log xml json");

    public static FileKind Of(string path)
    {
        var ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        if (ext == "pdf") return FileKind.Pdf;
        if (Images.Contains(ext)) return FileKind.Image;
        if (Videos.Contains(ext)) return FileKind.Video;
        if (Audio.Contains(ext)) return FileKind.Audio;
        if (Documents.Contains(ext)) return FileKind.Document;
        return FileKind.Other;
    }

    private static HashSet<string> Set(string list) => [.. list.Split(' ')];
}
