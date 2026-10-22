using System.Windows.Media;

namespace DragWheel;

/// <summary>The five "liquid glass" finishes, same palette as the macOS app.</summary>
public sealed record Theme(string Id, string Name, string Emoji, Color Glass, Color Petal, Color Accent,
                           Color Text, Color TextOnAccent, bool IsDark)
{
    public static readonly IReadOnlyList<Theme> All =
    [
        new("tangerine", "Liquid Tangerine", "🍊", Hex(0xFFF7EC, 0.88), Hex(0xFFFFFF, 0.92), Hex(0xFA6C1E), Hex(0x3A2414), Colors.White, false),
        new("neon", "Cyber Neon", "⚡", Hex(0x0B1020, 0.90), Hex(0x141C33, 0.95), Hex(0x00F2FE), Hex(0xCFEFFF), Hex(0x031018), true),
        new("emerald", "Emerald Forest", "🌲", Hex(0xEAF5EE, 0.88), Hex(0xF7FFFA, 0.92), Hex(0x10B981), Hex(0x0F3B2C), Colors.White, false),
        new("obsidian", "Midnight Obsidian", "🌑", Hex(0x050505, 0.92), Hex(0x1A1A1A, 0.95), Hex(0xE5E5E5), Hex(0xD4D4D4), Hex(0x0A0A0A), true),
        new("rose", "Sunset Rose", "🌸", Hex(0xFFEEF1, 0.88), Hex(0xFFFFFF, 0.92), Hex(0xF43F5E), Hex(0x4C1424), Colors.White, false),
    ];

    public static Theme Current => All.FirstOrDefault(t => t.Id == Core.Settings.Current.ThemeId) ?? All[0];

    private static Color Hex(uint rgb, double alpha = 1) =>
        Color.FromArgb((byte)Math.Round(alpha * 255), (byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);
}

public static class ColorExtensions
{
    public static SolidColorBrush Brush(this Color c, double opacity = 1)
    {
        var b = new SolidColorBrush(Color.FromArgb((byte)(c.A * opacity), c.R, c.G, c.B));
        b.Freeze();
        return b;
    }
}
