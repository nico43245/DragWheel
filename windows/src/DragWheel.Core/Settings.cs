using System.Text.Json;
using System.Text.Json.Serialization;

namespace DragWheel.Core;

public enum OutputLocation { NextToSource, CustomFolder }

/// <summary>User preferences, stored as JSON in %APPDATA%\DragWheel\settings.json.</summary>
public sealed class Settings
{
    // Computed, not stored: static initializers run in order and Load() below needs this path.
    public static string Folder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DragWheel");

    public static Settings Current { get; private set; } = Load();

    private static string FilePath => Path.Combine(Folder, "settings.json");

    [JsonConverter(typeof(JsonStringEnumConverter<OutputLocation>))]
    public OutputLocation OutputLocation { get; set; } = OutputLocation.NextToSource;
    public string CustomFolder { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    /// <summary>Lossy quality, 20–100.</summary>
    public int Quality { get; set; } = 80;
    public bool PlaySound { get; set; } = true;
    public bool RevealAfterConvert { get; set; }
    public string ThemeId { get; set; } = "tangerine";
    /// <summary>Show the wheel for drags from any app, not only File Explorer and the desktop.</summary>
    public bool WheelInAnyApp { get; set; }
    public bool WelcomeShown { get; set; }

    public event Action? Changed;

    public string OutputFolder(string source)
    {
        if (OutputLocation == OutputLocation.CustomFolder && !string.IsNullOrWhiteSpace(CustomFolder))
        {
            Directory.CreateDirectory(CustomFolder);
            return CustomFolder;
        }
        return Path.GetDirectoryName(Path.GetFullPath(source))!;
    }

    public void Save()
    {
        Quality = Math.Clamp(Quality, 20, 100);
        try
        {
            Directory.CreateDirectory(Folder);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (IOException) { /* settings are a convenience; never crash over them */ }
        Changed?.Invoke();
    }

    private static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch (Exception e) when (e is IOException or JsonException) { }
        return new Settings();
    }

    /// <summary>For tests: use throwaway settings.</summary>
    public static void UseForTesting(Settings settings) => Current = settings;
}
