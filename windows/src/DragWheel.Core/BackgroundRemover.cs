using ImageMagick;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace DragWheel.Core;

/// <summary>Cuts out the main subject with the U²-Net (u2netp) segmentation model, on the device.</summary>
public static class BackgroundRemover
{
    private const int Side = 320;
    private static readonly float[] Mean = [0.485f, 0.456f, 0.406f];
    private static readonly float[] Std = [0.229f, 0.224f, 0.225f];

    public static string ModelPath => Path.Combine(AppContext.BaseDirectory, "models", "u2netp.onnx");

    private static readonly Lazy<InferenceSession> Session = new(() =>
    {
        if (!File.Exists(ModelPath))
            throw new DragWheelException("The background-removal model is missing. Reinstall DragWheel.");
        return new InferenceSession(ModelPath);
    });

    public static string Remove(string input)
    {
        using var image = new MagickImage(input);
        image.AutoOrient();
        uint width = image.Width, height = image.Height;

        // 1. Model input: 320×320 RGB, ImageNet-normalised, channels first.
        using var small = (MagickImage)image.Clone();
        small.Alpha(AlphaAction.Remove);
        small.Resize(new MagickGeometry(Side, Side) { IgnoreAspectRatio = true });
        using var pixels = small.GetPixelsUnsafe();
        var rgb = pixels.ToByteArray(PixelMapping.RGB) ?? throw new DragWheelException("Couldn't read the image.");
        var tensor = new DenseTensor<float>([1, 3, Side, Side]);
        for (var y = 0; y < Side; y++)
            for (var x = 0; x < Side; x++)
                for (var c = 0; c < 3; c++)
                    tensor[0, c, y, x] = (rgb[(y * Side + x) * 3 + c] / 255f - Mean[c]) / Std[c];

        // 2. Run; the first output is the saliency map.
        var session = Session.Value;
        using var results = session.Run([NamedOnnxValue.CreateFromTensor(session.InputMetadata.Keys.First(), tensor)]);
        var map = results.First().AsTensor<float>();
        float min = float.MaxValue, max = float.MinValue;
        foreach (var v in map) { min = Math.Min(min, v); max = Math.Max(max, v); }
        if (max - min < 1e-6f) throw new DragWheelException($"No clear subject found in {Path.GetFileName(input)}.");

        // 3. Mask as a grey image, scaled back up, used as the alpha channel.
        var grey = new byte[Side * Side * 3];
        for (var y = 0; y < Side; y++)
            for (var x = 0; x < Side; x++)
            {
                var v = (byte)Math.Clamp((map[0, 0, y, x] - min) / (max - min) * 255f, 0, 255);
                var i = (y * Side + x) * 3;
                grey[i] = grey[i + 1] = grey[i + 2] = v;
            }
        using var mask = new MagickImage(MagickColors.Black, Side, Side);
        using (var maskPixels = mask.GetPixelsUnsafe()) maskPixels.SetArea(0, 0, Side, Side, grey);
        mask.Resize(new MagickGeometry(width, height) { IgnoreAspectRatio = true });

        image.Alpha(AlphaAction.Set);
        image.Composite(mask, CompositeOperator.CopyAlpha);

        var output = OutputNaming.File(input, "png", "_nobg");
        image.Write(output, MagickFormat.Png);
        return output;
    }
}
