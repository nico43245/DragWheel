using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage;

namespace DragWheel.Core;

/// <summary>Text recognition with Windows' built-in, on-device OCR.</summary>
public static class Ocr
{
    public static bool IsAvailable => Engine() is not null;

    private static OcrEngine? Engine() =>
        OcrEngine.TryCreateFromUserProfileLanguages()
        ?? OcrEngine.AvailableRecognizerLanguages.Select(OcrEngine.TryCreateFromLanguage).FirstOrDefault(e => e is not null);

    public static async Task<string> RecognizeFileAsync(string imagePath)
    {
        var engine = Engine() ?? throw new DragWheelException(
            "Windows has no text-recognition language installed. Add one in Settings → Time & language → Language.");

        // Normalise to a PNG Windows can decode, no larger than the engine accepts.
        var png = ImageOps.ToTemporaryPng(imagePath, OcrEngine.MaxImageDimension);
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(png);
            using var stream = await file.OpenAsync(FileAccessMode.Read);
            var decoder = await BitmapDecoder.CreateAsync(stream);
            using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            var result = await engine.RecognizeAsync(bitmap);
            return string.Join('\n', result.Lines.Select(l => l.Text));
        }
        finally
        {
            File.Delete(png);
        }
    }
}
