namespace DragWheel.Core;

/// <summary>Routes a wheel action to the right converter. Independent files run concurrently.</summary>
public static class ConversionEngine
{
    private static readonly SemaphoreSlim Slots = new(Math.Max(2, Environment.ProcessorCount / 2));

    public static async Task<IReadOnlyList<Outcome>> PerformAsync(ActionId action, IReadOnlyList<string> files)
    {
        if (files.Count == 0) return [];
        var paths = files.Select(Path.GetFullPath).ToList();

        switch (action)
        {
            case ActionId.mergePDF:
                return [await RunOne(paths[0], action, () => Task.FromResult<string?>(PdfOps.Merge(paths)))];

            case ActionId.toDOCX when paths.Count > 1 && paths.All(p => FileKinds.Of(p) == FileKind.Image):
                return [await RunOne(paths[0], action, () =>
                {
                    var output = OutputNaming.File(paths[0], "docx", "_images");
                    DocxWriter.Images(paths, output);
                    return Task.FromResult<string?>(output);
                })];

            case ActionId.edit or ActionId.annotate or ActionId.crop or ActionId.redact or ActionId.preview or ActionId.print:
                var opened = new List<Outcome>();
                foreach (var p in paths) opened.Add(await RunOne(p, action, () => { OpenInteractive(action, p); return Task.FromResult<string?>(null); }));
                return opened;

            default:
                var tasks = paths.Select(p => RunOne(p, action, async () =>
                {
                    await Slots.WaitAsync();
                    try { return await Task.Run(() => ConvertAsync(action, p)); }
                    finally { Slots.Release(); }
                }));
                return await Task.WhenAll(tasks);
        }
    }

    private static async Task<Outcome> RunOne(string source, ActionId action, Func<Task<string?>> work)
    {
        try { return new Outcome(source, action, await work(), null); }
        catch (DragWheelException e) { return new Outcome(source, action, null, e.Message); }
        catch (Exception e) { return new Outcome(source, action, null, $"{e.GetType().Name}: {e.Message}"); }
    }

    private static async Task<string?> ConvertAsync(ActionId action, string file)
    {
        var kind = FileKinds.Of(file);
        var name = Path.GetFileName(file);

        switch (action)
        {
            // Image formats — a video dropped on GIF becomes an animated GIF, a document on PDF becomes a PDF.
            case ActionId.toGIF when kind == FileKind.Video:
                return await MediaOps.ConvertAsync(file, "gif");
            case ActionId.toPDF when kind == FileKind.Document:
                return PdfOps.DocumentToPdf(file);
            case ActionId.toPDF when kind == FileKind.Pdf:
                throw new DragWheelException($"{name} is already a PDF.");
            case ActionId.toPDF:
                RequireImage(file, kind);
                var pdf = OutputNaming.File(file, "pdf");
                PdfOps.ImagesToPdf([file], pdf);
                return pdf;
            case ActionId.toDOCX when kind == FileKind.Pdf:
                return await PdfOps.ToWordAsync(file);
            case ActionId.toDOCX:
                RequireImage(file, kind);
                var docx = OutputNaming.File(file, "docx");
                DocxWriter.Images([file], docx);
                return docx;
            case ActionId.toPNG or ActionId.toWEBP or ActionId.toHEIC or ActionId.toGIF or ActionId.toAVIF
                or ActionId.toBMP or ActionId.toTIFF or ActionId.toJPEG:
                RequireImage(file, kind);
                return ImageOps.Convert(file, ImageExt(action));

            // Tools
            case ActionId.compressImage when kind == FileKind.Video: return await MediaOps.CompressAsync(file);
            case ActionId.compressImage when kind == FileKind.Pdf: return PdfOps.Compress(file);
            case ActionId.compressImage: RequireImage(file, kind); return ImageOps.Compress(file);
            case ActionId.stripMetadata: RequireImage(file, kind); return ImageOps.StripMetadata(file);
            case ActionId.removeBackground: RequireImage(file, kind); return BackgroundRemover.Remove(file);
            case ActionId.addBackground: RequireImage(file, kind); return ImageOps.AddBackground(file);

            // Video & audio
            case ActionId.toMP4 or ActionId.toMOV or ActionId.toWEBM or ActionId.videoToGIF:
                if (kind != FileKind.Video) throw new DragWheelException($"{name} isn't a video.");
                return await MediaOps.ConvertAsync(file, MediaExt(action));
            case ActionId.toMP3 or ActionId.toWAV or ActionId.toM4A:
                if (kind is not (FileKind.Video or FileKind.Audio)) throw new DragWheelException($"{name} has no audio to extract.");
                return await MediaOps.ConvertAsync(file, MediaExt(action));
            case ActionId.compressVideo:
                if (kind != FileKind.Video) throw new DragWheelException($"{name} isn't a video.");
                return await MediaOps.CompressAsync(file);
            case ActionId.mute:
                if (kind != FileKind.Video) throw new DragWheelException($"{name} isn't a video.");
                return await MediaOps.MuteAsync(file);

            // PDF & documents
            case ActionId.docToPDF when kind == FileKind.Image:
                var page = OutputNaming.File(file, "pdf");
                PdfOps.ImagesToPdf([file], page);
                return page;
            case ActionId.docToPDF when kind == FileKind.Document:
                return PdfOps.DocumentToPdf(file);
            case ActionId.docToPDF:
                throw new DragWheelException(kind == FileKind.Pdf ? $"{name} is already a PDF." : $"Can't turn {name} into a PDF.");
            case ActionId.compressPDF:
                RequirePdf(file, kind); return PdfOps.Compress(file);
            case ActionId.splitPDF:
                RequirePdf(file, kind); return PdfOps.Split(file);
            case ActionId.pdfToImages:
                RequirePdf(file, kind); return await PdfOps.ToImagesAsync(file);
            case ActionId.ocrText:
                return await PdfOps.OcrAsync(file);
            case ActionId.toWord:
                return await PdfOps.ToWordAsync(file);

            default:
                throw new DragWheelException($"Internal routing error for {action}.");
        }
    }

    private static void OpenInteractive(ActionId action, string file)
    {
        var kind = FileKinds.Of(file);
        switch (action)
        {
            case ActionId.print:
                if (kind is not (FileKind.Pdf or FileKind.Image or FileKind.Document))
                    throw new DragWheelException("Printing works for PDFs, images and documents.");
                ProcessRunner.Shell(file, "print");
                break;
            case ActionId.preview:
                ProcessRunner.Shell(file);
                break;
            default:
                // Edit, annotate, crop and redact: the image editor registered for "edit" (Photos or Paint).
                if (kind is not (FileKind.Image or FileKind.Pdf))
                    throw new DragWheelException("Editing works for images and PDFs.");
                try { ProcessRunner.Shell(file, kind == FileKind.Image ? "edit" : null); }
                catch (System.ComponentModel.Win32Exception) { ProcessRunner.Shell(file); }
                break;
        }
    }

    private static void RequireImage(string file, FileKind kind)
    {
        if (kind != FileKind.Image) throw new DragWheelException($"{Path.GetFileName(file)} isn't an image.");
    }

    private static void RequirePdf(string file, FileKind kind)
    {
        if (kind != FileKind.Pdf) throw new DragWheelException($"{Path.GetFileName(file)} isn't a PDF.");
    }

    private static string ImageExt(ActionId action) => action switch
    {
        ActionId.toPNG => "png",
        ActionId.toWEBP => "webp",
        ActionId.toHEIC => "heic",
        ActionId.toGIF => "gif",
        ActionId.toAVIF => "avif",
        ActionId.toBMP => "bmp",
        ActionId.toTIFF => "tiff",
        _ => "jpg",
    };

    private static string MediaExt(ActionId action) => action switch
    {
        ActionId.toMP4 => "mp4",
        ActionId.toMOV => "mov",
        ActionId.toWEBM => "webm",
        ActionId.videoToGIF => "gif",
        ActionId.toMP3 => "mp3",
        ActionId.toWAV => "wav",
        _ => "m4a",
    };
}
