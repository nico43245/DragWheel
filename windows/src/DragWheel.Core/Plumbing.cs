using System.Diagnostics;
using System.Text;

namespace DragWheel.Core;

/// <summary>An error worth showing to the user as-is.</summary>
public sealed class DragWheelException(string message) : Exception(message);

/// <summary>What happened to one input. <c>Output</c> is null when the action opened something instead of writing a file.</summary>
public sealed record Outcome(string Source, ActionId Action, string? Output, string? Error)
{
    public bool Succeeded => Error is null;
}

/// <summary>Picks output paths that never overwrite anything: photo.webp, photo_1.webp, photo_2.webp …</summary>
public static class OutputNaming
{
    public static string File(string source, string ext, string suffix = "")
    {
        var folder = Settings.Current.OutputFolder(source);
        var name = Path.GetFileNameWithoutExtension(source) + suffix;
        return Unique(folder, name, ext, source);
    }

    public static string Folder(string source, string suffix)
    {
        var parent = Settings.Current.OutputFolder(source);
        var name = Path.GetFileNameWithoutExtension(source) + suffix;
        var candidate = Path.Combine(parent, name);
        for (var n = 1; Directory.Exists(candidate) || System.IO.File.Exists(candidate); n++)
            candidate = Path.Combine(parent, $"{name}_{n}");
        return candidate;
    }

    public static string Unique(string folder, string name, string ext, string? avoid = null)
    {
        var candidate = Path.Combine(folder, $"{name}.{ext}");
        for (var n = 1; System.IO.File.Exists(candidate) || Directory.Exists(candidate)
                        || string.Equals(candidate, avoid, StringComparison.OrdinalIgnoreCase); n++)
            candidate = Path.Combine(folder, $"{name}_{n}.{ext}");
        return candidate;
    }

    public static string Temporary(string ext) =>
        Path.Combine(Path.GetTempPath(), $"dragwheel-{Guid.NewGuid():N}.{ext}");

    public static long Size(string path) => System.IO.File.Exists(path) ? new FileInfo(path).Length : 0;
}

/// <summary>Finds and runs ffmpeg (not bundled; installed by the user with winget).</summary>
public static class FFmpeg
{
    public const string InstallHint = "winget install Gyan.FFmpeg";

    public static string? Path => _path ??= Locate();
    private static string? _path;

    /// <summary>Forget the cached location, e.g. after the user installs ffmpeg.</summary>
    public static void Refresh() => _path = null;

    private static string? Locate()
    {
        var candidates = new List<string>();
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(System.IO.Path.PathSeparator))
            if (!string.IsNullOrWhiteSpace(dir)) candidates.Add(System.IO.Path.Combine(dir.Trim(), "ffmpeg.exe"));

        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        candidates.Add(System.IO.Path.Combine(local, "Microsoft", "WinGet", "Links", "ffmpeg.exe"));
        var packages = System.IO.Path.Combine(local, "Microsoft", "WinGet", "Packages");
        if (Directory.Exists(packages))
            foreach (var pkg in Directory.EnumerateDirectories(packages, "Gyan.FFmpeg*"))
                candidates.AddRange(Directory.EnumerateFiles(pkg, "ffmpeg.exe", SearchOption.AllDirectories));
        candidates.Add(@"C:\ffmpeg\bin\ffmpeg.exe");
        candidates.Add(@"C:\ProgramData\chocolatey\bin\ffmpeg.exe");

        return candidates.FirstOrDefault(System.IO.File.Exists);
    }

    public static async Task RunAsync(IEnumerable<string> arguments, string output)
    {
        var exe = Path ?? throw new DragWheelException($"ffmpeg is not installed. Install it with: {InstallHint}");
        try
        {
            await ProcessRunner.RunAsync(exe, ["-hide_banner", "-loglevel", "error", "-nostdin", "-y", .. arguments, output]);
        }
        catch
        {
            try { System.IO.File.Delete(output); } catch (IOException) { }
            throw;
        }
    }
}

public static class ProcessRunner
{
    /// <summary>Runs a program with an argument list (never through a shell) and throws with its stderr on failure.</summary>
    public static async Task RunAsync(string exe, IEnumerable<string> arguments)
    {
        var info = new ProcessStartInfo(exe)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
        };
        foreach (var a in arguments) info.ArgumentList.Add(a);

        using var process = Process.Start(info) ?? throw new DragWheelException($"Couldn't start {System.IO.Path.GetFileName(exe)}.");
        var stderr = process.StandardError.ReadToEndAsync();
        var stdout = process.StandardOutput.ReadToEndAsync();
        await process.WaitForExitAsync();
        await stdout;
        if (process.ExitCode != 0)
        {
            var tail = string.Join('\n', (await stderr).Trim().Split('\n').TakeLast(3));
            throw new DragWheelException($"{System.IO.Path.GetFileName(exe)} failed ({process.ExitCode}): {tail}");
        }
    }

    /// <summary>Opens a file with its default app, or with a shell verb such as "edit" or "print".</summary>
    public static void Shell(string path, string? verb = null)
    {
        var info = new ProcessStartInfo(path) { UseShellExecute = true };
        if (verb is not null) info.Verb = verb;
        Process.Start(info);
    }

    public static void RevealInExplorer(string path) =>
        Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { $"/select,{path}" }, UseShellExecute = false });
}

public static class Text
{
    /// <summary>"2.4 MB → 610 KB (75% smaller)"</summary>
    public static string SizeSummary(string source, string output)
    {
        if (Directory.Exists(output))
            return $"{Directory.GetFiles(output).Length} files in {System.IO.Path.GetFileName(output)}";
        long before = OutputNaming.Size(source), after = OutputNaming.Size(output);
        var text = $"{Bytes(before)} → {Bytes(after)}";
        if (before > 0 && after > 0)
        {
            var change = (int)Math.Round((1 - (double)after / before) * 100);
            if (change > 0) text += $" ({change}% smaller)";
            else if (change < 0) text += $" ({-change}% larger)";
        }
        return text;
    }

    public static string Bytes(long n) => n switch
    {
        < 1024 => $"{n} B",
        < 1024 * 1024 => $"{n / 1024.0:0} KB",
        < 1024L * 1024 * 1024 => $"{n / 1024.0 / 1024:0.0} MB",
        _ => $"{n / 1024.0 / 1024 / 1024:0.00} GB",
    };

    public static string XmlEscape(string s)
    {
        var b = new StringBuilder(s.Length);
        foreach (var c in s)
        {
            switch (c)
            {
                case '&': b.Append("&amp;"); break;
                case '<': b.Append("&lt;"); break;
                case '>': b.Append("&gt;"); break;
                case '"': b.Append("&quot;"); break;
                default:
                    // Drop control characters XML 1.0 can't carry.
                    if (c >= 0x20 || c is '\t' or '\n' or '\r') b.Append(c);
                    break;
            }
        }
        return b.ToString();
    }
}
