using System.Windows;
using DragWheel.Core;
using Microsoft.Win32;

namespace DragWheel;

public partial class PreferencesWindow : Window
{
    private static PreferencesWindow? _open;
    private readonly Settings _settings = Settings.Current;

    public static void ShowSingle()
    {
        _open ??= new PreferencesWindow();
        _open.Show();
        _open.Activate();
    }

    public PreferencesWindow()
    {
        InitializeComponent();
        Closed += (_, _) => _open = null;

        NextToSource.IsChecked = _settings.OutputLocation == OutputLocation.NextToSource;
        CustomFolder.IsChecked = !NextToSource.IsChecked;
        FolderPath.Text = _settings.CustomFolder;
        Quality.Value = _settings.Quality;
        QualityValue.Text = $"{_settings.Quality}%";
        PlaySound.IsChecked = _settings.PlaySound;
        Reveal.IsChecked = _settings.RevealAfterConvert;
        AnyApp.IsChecked = _settings.WheelInAnyApp;
        StartWithWindows.IsChecked = StartupRegistration.IsEnabled;
        ThemePicker.ItemsSource = Theme.All.Select(t => new { t.Id, Label = $"{t.Emoji}  {t.Name}" }).ToList();
        ThemePicker.SelectedValue = _settings.ThemeId;

        FFmpeg.Refresh();
        FFmpegStatus.Text = FFmpeg.Path is null ? $"Not installed — run: {FFmpeg.InstallHint}" : "✓ Installed";
        OcrStatus.Text = Ocr.IsAvailable ? "✓ Available" : "Add a language with OCR in Windows Settings";

        FolderRow.IsEnabled = CustomFolder.IsChecked == true;
        CustomFolder.Checked += (_, _) => FolderRow.IsEnabled = true;
        NextToSource.Checked += (_, _) => FolderRow.IsEnabled = false;
        Quality.ValueChanged += (_, _) => QualityValue.Text = $"{(int)Quality.Value}%";
    }

    private void ChooseFolder(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Where should DragWheel save converted files?", InitialDirectory = FolderPath.Text };
        if (dialog.ShowDialog(this) == true) FolderPath.Text = dialog.FolderName;
    }

    private void Done(object sender, RoutedEventArgs e)
    {
        _settings.OutputLocation = CustomFolder.IsChecked == true ? OutputLocation.CustomFolder : OutputLocation.NextToSource;
        _settings.CustomFolder = FolderPath.Text;
        _settings.Quality = (int)Quality.Value;
        _settings.PlaySound = PlaySound.IsChecked == true;
        _settings.RevealAfterConvert = Reveal.IsChecked == true;
        _settings.WheelInAnyApp = AnyApp.IsChecked == true;
        if (ThemePicker.SelectedValue is string theme) _settings.ThemeId = theme;
        _settings.Save();
        try { StartupRegistration.IsEnabled = StartWithWindows.IsChecked == true; }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException)
        {
            Toast.ShowError("Couldn't change the start-with-Windows setting.");
        }
        Close();
    }
}
