using System.IO.Compression;
using DragWheel.Core;
using ImageMagick;
using ImageMagick.Drawing;
using PdfSharp.Pdf.IO;
using Xunit;

namespace DragWheel.Core.Tests;

/// <summary>Runs the real converters on generated sample files and checks what comes out.</summary>
public sealed class ConversionTests : IDisposable
{
    private readonly string _dir = Directory.CreateTempSubdirectory("dragwheel-tests-").FullName;

    public ConversionTests() => Settings.UseForTesting(new Settings());

    public void Dispose()
    {
        try { Directory.Delete(_dir, recursive: true); } catch (IOException) { }
    }

    private string SamplePhoto(bool alpha = false)
    {
        var path = Path.Combine(_dir, alpha ? "logo.png" : "photo.png");
        using var image = new MagickImage(alpha ? MagickColors.Transparent : MagickColors.White, 640, 400);
        new Drawables()
            .FillColor(MagickColors.OrangeRed).Rectangle(40, 40, 600, 160)
            .FillColor(MagickColors.Black).FontPointSize(48).Text(60, 280, "DragWheel test 123")
            .Draw(image);
        image.Write(path, MagickFormat.Png);
        return path;
    }

    private string SampleText()
    {
        var path = Path.Combine(_dir, "note.txt");
        File.WriteAllText(path, "Hello from DragWheel.\nSecond line.");
        return path;
    }

    private static string Single(IReadOnlyList<Outcome> outcomes)
    {
        var o = Assert.Single(outcomes);
        Assert.True(o.Succeeded, o.Error);
        Assert.NotNull(o.Output);
        Assert.True(File.Exists(o.Output) || Directory.Exists(o.Output), $"missing {o.Output}");
        return o.Output!;
    }

    [Theory]
    [InlineData(ActionId.toPNG, MagickFormat.Png)]
    [InlineData(ActionId.toJPEG, MagickFormat.Jpeg)]
    [InlineData(ActionId.toWEBP, MagickFormat.WebP)]
    [InlineData(ActionId.toGIF, MagickFormat.Gif)]
    [InlineData(ActionId.toBMP, MagickFormat.Bmp)]
    [InlineData(ActionId.toTIFF, MagickFormat.Tiff)]
    [InlineData(ActionId.toAVIF, MagickFormat.Avif)]
    [InlineData(ActionId.toHEIC, MagickFormat.Heic)]
    public async Task ConvertsImages(ActionId action, MagickFormat expected)
    {
        var output = Single(await ConversionEngine.PerformAsync(action, [SamplePhoto()]));
        var info = new MagickImageInfo(output);
        Assert.Equal(expected, info.Format);
        Assert.Equal(640u, info.Width);
    }

    [Fact]
    public async Task NeverOverwrites()
    {
        var photo = SamplePhoto();
        var first = Single(await ConversionEngine.PerformAsync(ActionId.toJPEG, [photo]));
        var second = Single(await ConversionEngine.PerformAsync(ActionId.toJPEG, [photo]));
        Assert.NotEqual(first, second);
        Assert.EndsWith("photo_1.jpg", second);
    }

    [Fact]
    public async Task ImageToPdfAndWord()
    {
        var photo = SamplePhoto();
        using (var pdf = PdfReader.Open(Single(await ConversionEngine.PerformAsync(ActionId.toPDF, [photo])), PdfDocumentOpenMode.Import))
            Assert.Equal(1, pdf.PageCount);

        using var docx = ZipFile.OpenRead(Single(await ConversionEngine.PerformAsync(ActionId.toDOCX, [photo])));
        Assert.NotNull(docx.GetEntry("word/media/image1.png"));
        Assert.NotNull(docx.GetEntry("word/document.xml"));
    }

    [Fact]
    public async Task ImageTools()
    {
        var logo = SamplePhoto(alpha: true);
        var flat = Single(await ConversionEngine.PerformAsync(ActionId.addBackground, [logo]));
        using (var image = new MagickImage(flat)) Assert.False(image.HasAlpha);

        var clean = Single(await ConversionEngine.PerformAsync(ActionId.stripMetadata, [SamplePhoto()]));
        using (var image = new MagickImage(clean)) Assert.Null(image.GetExifProfile());
    }

    [Fact]
    public async Task RemovesBackgroundWhenModelIsPresent()
    {
        Assert.SkipUnless(File.Exists(BackgroundRemover.ModelPath), "u2netp.onnx not downloaded");
        var output = Single(await ConversionEngine.PerformAsync(ActionId.removeBackground, [SamplePhoto()]));
        using var image = new MagickImage(output);
        Assert.True(image.HasAlpha);
    }

    [Fact]
    public async Task PdfWorkflow()
    {
        var notePdf = Single(await ConversionEngine.PerformAsync(ActionId.docToPDF, [SampleText()]));
        var merged = Single(await ConversionEngine.PerformAsync(ActionId.mergePDF, [notePdf, SamplePhoto()]));
        using (var pdf = PdfReader.Open(merged, PdfDocumentOpenMode.Import)) Assert.Equal(2, pdf.PageCount);

        var pages = Single(await ConversionEngine.PerformAsync(ActionId.splitPDF, [merged]));
        Assert.Equal(2, Directory.GetFiles(pages, "*.pdf").Length);

        var images = Single(await ConversionEngine.PerformAsync(ActionId.pdfToImages, [merged]));
        Assert.Equal(2, Directory.GetFiles(images, "*.png").Length);

        var word = Single(await ConversionEngine.PerformAsync(ActionId.toWord, [notePdf]));
        using var docx = ZipFile.OpenRead(word);
        using var reader = new StreamReader(docx.GetEntry("word/document.xml")!.Open());
        Assert.Contains("Hello from DragWheel", reader.ReadToEnd());
    }

    [Fact]
    public async Task RecognizesText()
    {
        Assert.SkipUnless(Ocr.IsAvailable, "no Windows OCR language on this machine");
        var text = File.ReadAllText(Single(await ConversionEngine.PerformAsync(ActionId.ocrText, [SamplePhoto()])));
        Assert.Contains("DragWheel", text, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task RefusesWrongInput()
    {
        var photo = SamplePhoto();
        var o = Assert.Single(await ConversionEngine.PerformAsync(ActionId.splitPDF, [photo]));
        Assert.False(o.Succeeded);
        Assert.Contains("isn't a PDF", o.Error);
    }

    [Theory]
    [InlineData(ActionId.toMP4)]
    [InlineData(ActionId.toMP3)]
    [InlineData(ActionId.toWAV)]
    [InlineData(ActionId.toWEBM)]
    [InlineData(ActionId.toM4A)]
    [InlineData(ActionId.videoToGIF)]
    [InlineData(ActionId.mute)]
    public async Task ConvertsMedia(ActionId action)
    {
        Assert.SkipWhen(FFmpeg.Path is null, "ffmpeg not installed");
        var clip = Path.Combine(_dir, "clip.mov");
        await ProcessRunner.RunAsync(FFmpeg.Path!, ["-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=size=320x240:rate=24:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", clip]);
        var output = Single(await ConversionEngine.PerformAsync(action, [clip]));
        Assert.True(new FileInfo(output).Length > 0);
    }

    [Fact]
    public void PicksPageByFileType()
    {
        Assert.Equal(0, Catalog.BestPage(["a.heic"]));
        Assert.Equal(2, Catalog.BestPage(["a.mp4"]));
        Assert.Equal(3, Catalog.BestPage(["a.pdf"]));
        Assert.All(Catalog.Pages, p => Assert.Equal(8, p.Petals.Count));
    }
}
