using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using ImageMagick;
using MigraDoc.DocumentObjectModel;
using MigraDoc.Rendering;
using PdfSharp.Drawing;
using PdfSharp.Fonts;
using PdfSharp.Pdf;
using PdfSharp.Pdf.IO;
using UglyToad.PdfPig.DocumentLayoutAnalysis.TextExtractor;
using Windows.Data.Pdf;
using Windows.Storage;
using Windows.Storage.Streams;
using SharpDocument = PdfSharp.Pdf.PdfDocument;
using WinPdfDocument = Windows.Data.Pdf.PdfDocument;

namespace DragWheel.Core;

/// <summary>PDF and document work: PDFsharp/MigraDoc for writing, PdfPig for text, Windows' own PDF renderer for pages.</summary>
public static partial class PdfOps
{
    static PdfOps()
    {
        // Use the fonts installed in Windows for text documents.
        if (OperatingSystem.IsWindows()) GlobalFontSettings.UseWindowsFontsUnderWindows = true;
    }

    // MARK: Writing

    /// <summary>Images (one page each, sized to the image) into a PDF.</summary>
    public static void ImagesToPdf(IEnumerable<string> images, string output)
    {
        using var pdf = new SharpDocument();
        foreach (var path in images) AddImagePage(pdf, path);
        pdf.Save(output);
    }

    private static void AddImagePage(SharpDocument pdf, string path)
    {
        using var image = new MagickImage(path);
        image.AutoOrient();
        using var png = new MemoryStream(image.ToByteArray(MagickFormat.Png));
        using var x = XImage.FromStream(png);
        var page = pdf.AddPage();
        page.Width = XUnit.FromPoint(image.Width * 72.0 / 96);
        page.Height = XUnit.FromPoint(image.Height * 72.0 / 96);
        using var g = XGraphics.FromPdfPage(page);
        g.DrawImage(x, 0, 0, page.Width.Point, page.Height.Point);
    }

    /// <summary>Text, Markdown, RTF, HTML or Word → A4 PDF. Formatting is simplified to paragraphs.</summary>
    public static string DocumentToPdf(string input)
    {
        var output = OutputNaming.File(input, "pdf");
        var doc = new Document();
        var style = doc.Styles[StyleNames.Normal]!;
        style.Font.Name = "Segoe UI";
        style.Font.Size = 11;
        style.ParagraphFormat.SpaceAfter = Unit.FromPoint(6);
        var section = doc.AddSection();
        section.PageSetup = doc.DefaultPageSetup.Clone();
        section.PageSetup.PageFormat = PageFormat.A4;
        section.PageSetup.TopMargin = section.PageSetup.BottomMargin = Unit.FromCentimeter(2);
        section.PageSetup.LeftMargin = section.PageSetup.RightMargin = Unit.FromCentimeter(2);

        foreach (var paragraph in ReadParagraphs(input)) section.AddParagraph(paragraph);

        var renderer = new PdfDocumentRenderer { Document = doc };
        renderer.RenderDocument();
        renderer.PdfDocument.Save(output);
        return output;
    }

    // MARK: Editing

    public static string Compress(string input)
    {
        var output = OutputNaming.File(input, "pdf", "_compressed");
        using (var pdf = Open(input, PdfDocumentOpenMode.Modify))
        {
            pdf.Options.CompressContentStreams = true;
            pdf.Options.NoCompression = false;
            pdf.Options.FlateEncodeMode = PdfFlateEncodeMode.BestCompression;
            pdf.Options.UseFlateDecoderForJpegImages = PdfUseFlateDecoderForJpegImages.Automatic;
            pdf.Save(output);
        }
        if (OutputNaming.Size(output) >= OutputNaming.Size(input))
        {
            File.Delete(output);
            throw new DragWheelException($"{Path.GetFileName(input)} is already as small as it gets.");
        }
        return output;
    }

    /// <summary>One PDF per page, in a new folder next to the original.</summary>
    public static string Split(string input)
    {
        using var source = Open(input, PdfDocumentOpenMode.Import);
        if (source.PageCount < 2) throw new DragWheelException($"{Path.GetFileName(input)} has only one page.");
        var folder = OutputNaming.Folder(input, "_pages");
        Directory.CreateDirectory(folder);
        var name = Path.GetFileNameWithoutExtension(input);
        var digits = source.PageCount.ToString().Length;
        for (var i = 0; i < source.PageCount; i++)
        {
            using var single = new SharpDocument();
            single.AddPage(source.Pages[i]);
            single.Save(Path.Combine(folder, $"{name}_p{(i + 1).ToString().PadLeft(digits, '0')}.pdf"));
        }
        return folder;
    }

    /// <summary>PDFs and images, in the order given, into one PDF.</summary>
    public static string Merge(IReadOnlyList<string> inputs)
    {
        if (inputs.Count < 2) throw new DragWheelException("Drop two or more files to merge them.");
        using var merged = new SharpDocument();
        foreach (var path in inputs)
        {
            switch (FileKinds.Of(path))
            {
                case FileKind.Pdf:
                    using (var source = Open(path, PdfDocumentOpenMode.Import))
                        foreach (var page in source.Pages) merged.AddPage(page);
                    break;
                case FileKind.Image:
                    AddImagePage(merged, path);
                    break;
                default:
                    throw new DragWheelException($"{Path.GetFileName(path)} can't be merged into a PDF.");
            }
        }
        var output = OutputNaming.Unique(Settings.Current.OutputFolder(inputs[0]), "Merged", "pdf");
        merged.Save(output);
        return output;
    }

    // MARK: Pages & text

    /// <summary>Every page as a PNG at 2× (144 dpi), in a new folder.</summary>
    public static async Task<string> ToImagesAsync(string input)
    {
        var pdf = await LoadForRendering(input);
        var folder = OutputNaming.Folder(input, "_images");
        Directory.CreateDirectory(folder);
        var name = Path.GetFileNameWithoutExtension(input);
        for (uint i = 0; i < pdf.PageCount; i++)
            await RenderPageAsync(pdf, i, Path.Combine(folder, $"{name}_p{i + 1}.png"), 2);
        return folder;
    }

    public static async Task<string> OcrAsync(string input)
    {
        var text = await ExtractTextAsync(input, forceOcr: FileKinds.Of(input) == FileKind.Image);
        if (string.IsNullOrWhiteSpace(text.Replace("\f", "")))
            throw new DragWheelException($"No text found in {Path.GetFileName(input)}.");
        var output = OutputNaming.File(input, "txt", "_text");
        await File.WriteAllTextAsync(output, text.Replace("\f", "\n\n"), new UTF8Encoding(true));
        return output;
    }

    /// <summary>PDF or image → editable Word document (text only).</summary>
    public static async Task<string> ToWordAsync(string input)
    {
        var text = await ExtractTextAsync(input, forceOcr: false);
        if (string.IsNullOrWhiteSpace(text.Replace("\f", "")))
            throw new DragWheelException($"No text found in {Path.GetFileName(input)}.");
        var output = OutputNaming.File(input, "docx");
        var paragraphs = text.Split('\f').SelectMany((page, i) =>
            (i > 0 ? new[] { "\f" } : []).Concat(page.Replace("\r", "").Split('\n')));
        DocxWriter.Paragraphs(paragraphs, output);
        return output;
    }

    /// <summary>Pages are separated by form feeds. Uses the PDF's text layer when it has one, OCR otherwise.</summary>
    public static async Task<string> ExtractTextAsync(string input, bool forceOcr)
    {
        switch (FileKinds.Of(input))
        {
            case FileKind.Image:
                return await Ocr.RecognizeFileAsync(input);
            case FileKind.Pdf:
                var pages = new List<string>();
                if (!forceOcr)
                {
                    using var doc = UglyToad.PdfPig.PdfDocument.Open(input);
                    foreach (var page in doc.GetPages()) pages.Add(ContentOrderTextExtractor.GetText(page).Trim());
                }
                if (pages.All(string.IsNullOrWhiteSpace))
                {
                    pages.Clear();
                    var pdf = await LoadForRendering(input);
                    for (uint i = 0; i < pdf.PageCount; i++)
                    {
                        var png = OutputNaming.Temporary("png");
                        try
                        {
                            await RenderPageAsync(pdf, i, png, 2);
                            pages.Add(await Ocr.RecognizeFileAsync(png));
                        }
                        finally { File.Delete(png); }
                    }
                }
                return string.Join('\f', pages);
            default:
                throw new DragWheelException("Text recognition works for images and PDFs.");
        }
    }

    // MARK: Helpers

    private static SharpDocument Open(string path, PdfDocumentOpenMode mode)
    {
        try { return PdfReader.Open(path, mode); }
        catch (PdfReaderException e) { throw new DragWheelException($"Can't open {Path.GetFileName(path)}: {e.Message}"); }
    }

    private static async Task<WinPdfDocument> LoadForRendering(string path)
    {
        var file = await StorageFile.GetFileFromPathAsync(Path.GetFullPath(path));
        try { return await WinPdfDocument.LoadFromFileAsync(file); }
        catch (Exception e) when (e is not DragWheelException)
        {
            throw new DragWheelException($"Can't open {Path.GetFileName(path)} (is it password protected?)");
        }
    }

    private static async Task RenderPageAsync(WinPdfDocument pdf, uint index, string output, double scale)
    {
        using var page = pdf.GetPage(index);
        using var stream = new InMemoryRandomAccessStream();
        await page.RenderToStreamAsync(stream, new PdfPageRenderOptions
        {
            DestinationWidth = (uint)Math.Round(page.Size.Width * scale),
            DestinationHeight = (uint)Math.Round(page.Size.Height * scale),
            BackgroundColor = Windows.UI.Color.FromArgb(255, 255, 255, 255),
        });
        stream.Seek(0);
        await using var file = File.Create(output);
        await stream.AsStreamForRead().CopyToAsync(file);
    }

    /// <summary>Plain paragraphs from the common text formats.</summary>
    public static IEnumerable<string> ReadParagraphs(string input)
    {
        var ext = Path.GetExtension(input).TrimStart('.').ToLowerInvariant();
        string text = ext switch
        {
            "docx" => DocxText(input),
            "rtf" => RtfText(File.ReadAllText(input)),
            "html" or "htm" => HtmlText(File.ReadAllText(input)),
            "odt" => throw new DragWheelException("OpenDocument files aren't supported yet — save as .docx first."),
            _ => File.ReadAllText(input),
        };
        return text.Replace("\r\n", "\n").Split('\n');
    }

    private static string DocxText(string path)
    {
        using var zip = System.IO.Compression.ZipFile.OpenRead(path);
        var entry = zip.GetEntry("word/document.xml") ?? throw new DragWheelException($"{Path.GetFileName(path)} isn't a Word document.");
        using var reader = new StreamReader(entry.Open());
        var xml = reader.ReadToEnd();
        var result = new StringBuilder();
        foreach (Match p in ParagraphRegex().Matches(xml))
        {
            foreach (Match t in TextRunRegex().Matches(p.Value)) result.Append(WebUtility.HtmlDecode(t.Groups[1].Value));
            result.Append('\n');
        }
        return result.ToString();
    }

    /// <summary>Good enough for the RTF that WordPad and TextEdit write.</summary>
    private static string RtfText(string rtf)
    {
        var s = Regex.Replace(rtf, @"\{\\\*[^{}]*\}|\{\\fonttbl[^}]*\}+|\{\\colortbl[^}]*\}", "");
        s = Regex.Replace(s, @"\\par[d]?\b ?", "\n");
        s = Regex.Replace(s, @"\\'([0-9a-fA-F]{2})", m => ((char)System.Convert.ToInt32(m.Groups[1].Value, 16)).ToString());
        s = Regex.Replace(s, @"\\u(-?\d+)\??", m => ((char)(short)int.Parse(m.Groups[1].Value)).ToString());
        s = Regex.Replace(s, @"\\[a-zA-Z]+-?\d* ?", "");
        return s.Replace("{", "").Replace("}", "").Replace("\\\\", "\\").Trim();
    }

    private static string HtmlText(string html)
    {
        var s = Regex.Replace(html, @"<(script|style)[\s\S]*?</\1>", "", RegexOptions.IgnoreCase);
        s = Regex.Replace(s, @"<(br|/p|/div|/h\d|/li)[^>]*>", "\n", RegexOptions.IgnoreCase);
        s = Regex.Replace(s, "<[^>]+>", "");
        return WebUtility.HtmlDecode(s).Trim();
    }

    [GeneratedRegex(@"<w:p[ >][\s\S]*?</w:p>")]
    private static partial Regex ParagraphRegex();

    [GeneratedRegex(@"<w:t(?: [^>]*)?>([^<]*)</w:t>")]
    private static partial Regex TextRunRegex();
}
