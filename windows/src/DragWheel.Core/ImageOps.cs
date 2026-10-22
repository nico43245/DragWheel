using ImageMagick;

namespace DragWheel.Core;

/// <summary>Image conversion and editing with Magick.NET (in-process, no external tools).</summary>
public static class ImageOps
{
    public static string Convert(string input, string ext)
    {
        var output = OutputNaming.File(input, ext);
        Write(input, output, ext, Settings.Current.Quality, keepMetadata: true);
        return output;
    }

    public static MagickFormat FormatFor(string ext) => ext switch
    {
        "png" => MagickFormat.Png,
        "jpg" or "jpeg" => MagickFormat.Jpeg,
        "webp" => MagickFormat.WebP,
        "heic" => MagickFormat.Heic,
        "avif" => MagickFormat.Avif,
        "gif" => MagickFormat.Gif,
        "bmp" => MagickFormat.Bmp,
        "tif" or "tiff" => MagickFormat.Tiff,
        _ => throw new DragWheelException($"Unsupported image format: {ext}"),
    };

    /// <summary>Animated GIFs and multi-page TIFFs keep their frames when the target can hold them.</summary>
    public static void Write(string input, string output, string ext, int quality, bool keepMetadata)
    {
        var format = FormatFor(ext);
        try
        {
            if (format is MagickFormat.Gif or MagickFormat.Tiff or MagickFormat.WebP)
            {
                using var frames = new MagickImageCollection(input);
                if (frames.Count > 1)
                {
                    if (format == MagickFormat.Gif) frames.Optimize();
                    foreach (var f in frames) Prepare(f, quality, keepMetadata);
                    frames.Write(output, format);
                    return;
                }
            }
            using var image = new MagickImage(input);
            Prepare(image, quality, keepMetadata);
            if (format is MagickFormat.Jpeg or MagickFormat.Bmp && image.HasAlpha)
            {
                // These formats can't hold transparency: put it on white instead of black.
                image.BackgroundColor = MagickColors.White;
                image.Alpha(AlphaAction.Remove);
            }
            image.Write(output, format);
        }
        catch (MagickException e)
        {
            try { File.Delete(output); } catch (IOException) { }
            throw new DragWheelException($"Couldn't convert {Path.GetFileName(input)} to {ext.ToUpperInvariant()}: {e.Message}");
        }
    }

    private static void Prepare(IMagickImage<byte> image, int quality, bool keepMetadata)
    {
        image.AutoOrient();     // bake the rotation into the pixels so every viewer shows it upright
        image.Quality = (uint)Math.Clamp(quality, 1, 100);
        if (!keepMetadata) image.Strip();
    }

    /// <summary>Re-encodes at the chosen quality: transparent images go to WebP, opaque ones to JPEG.
    /// Keeps the result only if it's actually smaller.</summary>
    public static string Compress(string input)
    {
        var ext = Path.GetExtension(input).TrimStart('.').ToLowerInvariant();
        var quality = Math.Min(Settings.Current.Quality, 75);
        string target;
        if (ext is "jpg" or "jpeg" or "heic" or "avif" or "webp") target = ext;
        else
        {
            using var info = new MagickImage(input);
            target = info.HasAlpha ? "webp" : "jpg";
        }
        var output = OutputNaming.File(input, target, "_compressed");
        Write(input, output, target, quality, keepMetadata: true);
        if (OutputNaming.Size(output) >= OutputNaming.Size(input))
        {
            File.Delete(output);
            throw new DragWheelException($"{Path.GetFileName(input)} is already as small as it gets.");
        }
        return output;
    }

    /// <summary>Removes EXIF, GPS, XMP and comments; keeps the picture the right way up.</summary>
    public static string StripMetadata(string input)
    {
        var ext = Path.GetExtension(input).TrimStart('.').ToLowerInvariant();
        try { FormatFor(ext); } catch (DragWheelException) { ext = "png"; }
        var output = OutputNaming.File(input, ext, "_clean");
        Write(input, output, ext, 95, keepMetadata: false);
        return output;
    }

    /// <summary>Flattens transparency onto white.</summary>
    public static string AddBackground(string input)
    {
        var output = OutputNaming.File(input, "png", "_bg");
        using var image = new MagickImage(input);
        image.AutoOrient();
        image.BackgroundColor = MagickColors.White;
        image.Alpha(AlphaAction.Remove);
        image.Alpha(AlphaAction.Off);
        image.Write(output, MagickFormat.Png);
        return output;
    }

    /// <summary>A PNG copy, for tools that only read common formats.</summary>
    public static string ToTemporaryPng(string input, uint maxDimension = 0)
    {
        var temp = OutputNaming.Temporary("png");
        using var image = new MagickImage(input);
        image.AutoOrient();
        if (maxDimension > 0 && Math.Max(image.Width, image.Height) > maxDimension)
            image.Resize(new MagickGeometry(maxDimension, maxDimension));
        image.Write(temp, MagickFormat.Png);
        return temp;
    }
}
