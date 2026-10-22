namespace DragWheel.Core;

/// <summary>Video and audio through ffmpeg.</summary>
public static class MediaOps
{
    public static async Task<string> ConvertAsync(string input, string ext)
    {
        var output = OutputNaming.File(input, ext);
        var q = Settings.Current.Quality;
        var crf = q >= 85 ? "20" : q >= 60 ? "23" : "28";
        string[] args = ext switch
        {
            "mp4" => ["-i", input, "-c:v", "libx264", "-crf", crf, "-preset", "medium", "-pix_fmt", "yuv420p",
                      "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart"],
            "mov" => ["-i", input, "-c:v", "libx264", "-crf", crf, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k"],
            "webm" => ["-i", input, "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1", "-c:a", "libopus"],
            "mp3" => ["-i", input, "-vn", "-c:a", "libmp3lame", "-q:a", "2"],
            "wav" => ["-i", input, "-vn", "-c:a", "pcm_s16le"],
            "m4a" => ["-i", input, "-vn", "-c:a", "aac", "-b:a", "192k"],
            "gif" => ["-i", input, "-vf",
                      "fps=12,scale='min(640,iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
                      "-loop", "0"],
            _ => throw new DragWheelException($"Unsupported media format: {ext}"),
        };
        await FFmpeg.RunAsync(args, output);
        return output;
    }

    public static async Task<string> CompressAsync(string input)
    {
        var output = OutputNaming.File(input, "mp4", "_compressed");
        await FFmpeg.RunAsync(["-i", input, "-c:v", "libx264", "-crf", "28", "-preset", "slow", "-pix_fmt", "yuv420p",
                               "-vf", "scale='min(1920,iw)':-2", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"], output);
        if (OutputNaming.Size(output) >= OutputNaming.Size(input))
        {
            File.Delete(output);
            throw new DragWheelException($"{Path.GetFileName(input)} is already well compressed.");
        }
        return output;
    }

    public static async Task<string> MuteAsync(string input)
    {
        var ext = Path.GetExtension(input).TrimStart('.');
        var output = OutputNaming.File(input, string.IsNullOrEmpty(ext) ? "mp4" : ext.ToLowerInvariant(), "_muted");
        await FFmpeg.RunAsync(["-i", input, "-map", "0", "-map", "-0:a", "-c", "copy"], output);
        return output;
    }
}
