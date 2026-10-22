using System.Windows;
using DragWheel.Core;
using Forms = System.Windows.Forms;

namespace DragWheel;

/// <summary>The notification-area icon and its menu.</summary>
internal sealed class TrayIcon : IDisposable
{
    private readonly Forms.NotifyIcon _icon;

    public TrayIcon()
    {
        var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/DragWheel.ico"))!.Stream;
        _icon = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream),
            Text = "DragWheel — hold Shift while dragging a file",
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip(),
        };
        _icon.ContextMenuStrip.Opening += (_, _) => Build();
        _icon.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) ConverterWindow.ShowSingle(); };
        Build();
    }

    /// <summary>Rebuilt every time it opens so Recent, theme and ffmpeg state are current.</summary>
    private void Build()
    {
        var menu = _icon.ContextMenuStrip!;
        menu.Items.Clear();
        menu.Items.Add(new Forms.ToolStripMenuItem("Hold Shift while dragging a file") { Enabled = false });
        if (FFmpeg.Path is null)
            menu.Items.Add(new Forms.ToolStripMenuItem($"⚠ ffmpeg missing: {FFmpeg.InstallHint}", null,
                (_, _) => System.Windows.Clipboard.SetText(FFmpeg.InstallHint)) { ToolTipText = "Click to copy the command" });
        menu.Items.Add(new Forms.ToolStripSeparator());

        menu.Items.Add("Open Converter Window…", null, (_, _) => ConverterWindow.ShowSingle());

        var clipboard = new Forms.ToolStripMenuItem("Convert Clipboard Image");
        foreach (var (title, action) in new[] { ("PNG", ActionId.toPNG), ("JPEG", ActionId.toJPEG), ("WEBP", ActionId.toWEBP), ("PDF", ActionId.toPDF), ("Text (OCR)", ActionId.ocrText) })
            clipboard.DropDownItems.Add(title, null, (_, _) => _ = ClipboardConverter.ConvertAsync(action));
        menu.Items.Add(clipboard);

        var recent = new Forms.ToolStripMenuItem("Recent");
        if (Runner.History.Count == 0) recent.DropDownItems.Add(new Forms.ToolStripMenuItem("Nothing yet") { Enabled = false });
        foreach (var h in Runner.History.Take(10))
        {
            var item = new Forms.ToolStripMenuItem((h.Output is null ? "✗ " : "✓ ") + h.Title) { ToolTipText = h.Error };
            if (h.Output is { } output) item.Click += (_, _) => ProcessRunner.RevealInExplorer(output);
            recent.DropDownItems.Add(item);
        }
        menu.Items.Add(recent);

        var themes = new Forms.ToolStripMenuItem("Theme");
        foreach (var theme in Theme.All)
        {
            var id = theme.Id;
            themes.DropDownItems.Add(new Forms.ToolStripMenuItem($"{theme.Emoji}  {theme.Name}", null, (_, _) =>
            {
                Settings.Current.ThemeId = id;
                Settings.Current.Save();
            }) { Checked = Settings.Current.ThemeId == id });
        }
        menu.Items.Add(themes);

        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Preferences…", null, (_, _) => PreferencesWindow.ShowSingle());
        menu.Items.Add("Quit DragWheel", null, (_, _) => Application.Current.Shutdown());
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}

internal static class ClipboardConverter
{
    /// <summary>Saves the clipboard image to Downloads, then runs the action on it.</summary>
    public static async Task ConvertAsync(ActionId action)
    {
        if (!System.Windows.Clipboard.ContainsImage())
        {
            Toast.ShowError("There's no image on the clipboard.");
            return;
        }
        var image = System.Windows.Clipboard.GetImage();
        var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        Directory.CreateDirectory(downloads);
        var source = OutputNaming.Unique(downloads, $"Clipboard {DateTime.Now:yyyy-MM-dd HH-mm-ss}", "png");
        await using (var file = File.Create(source))
        {
            var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
            encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(image));
            encoder.Save(file);
        }
        if (action == ActionId.toPNG)
        {
            Toast.Show(Path.GetFileName(source), "Saved from the clipboard", [source]);
            return;
        }
        await Runner.RunAsync(action, [source]);
        File.Delete(source);
    }
}
