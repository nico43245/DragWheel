using DragWheel.Core;

namespace DragWheel;

/// <summary>Which page is showing and which petal is under the cursor. Geometry in DIPs, origin top-left.</summary>
public sealed class WheelState
{
    public const double Size = 440;
    public const double InnerRadius = 72;
    public const double OuterRadius = 168;
    public const double CenterRadius = 62;
    public const int PetalCount = 8;
    public const int CenterIndex = 8;

    public int PageIndex { get; private set; }
    /// <summary>0..7 for petals, 8 for the center button.</summary>
    public int? Hovered { get; private set; }
    public IReadOnlyList<string> Files { get; private set; } = [];

    public event Action? Changed;

    public WheelPage Page => Catalog.Pages[PageIndex];

    public WheelAction? HoveredAction => Hovered switch
    {
        null => null,
        CenterIndex => Page.Center,
        var i => Page.Petals[i.Value],
    };

    // Windows only reveals the dragged files once the drag reaches the wheel, so the page
    // follows the file type until the user picks a page themselves.
    private bool _pageFollowsFiles;

    public void Reset(IReadOnlyList<string> files, bool toolsPage)
    {
        Files = files;
        PageIndex = toolsPage ? 1 : Catalog.BestPage(files);
        _pageFollowsFiles = !toolsPage;
        Hovered = null;
        Changed?.Invoke();
    }

    public void SetFiles(IReadOnlyList<string> files)
    {
        if (files.SequenceEqual(Files)) return;
        Files = files;
        if (_pageFollowsFiles) PageIndex = Catalog.BestPage(files);
        Changed?.Invoke();
    }

    public void SwitchPage(int step)
    {
        _pageFollowsFiles = false;
        var count = Catalog.Pages.Count;
        PageIndex = ((PageIndex + step) % count + count) % count;
        Changed?.Invoke();
    }

    public void UpdateHover(double x, double y)
    {
        double dx = x - Size / 2, dy = y - Size / 2, distance = Math.Sqrt(dx * dx + dy * dy);
        int? value = distance <= CenterRadius ? CenterIndex
            : distance >= InnerRadius - 6 && distance <= OuterRadius + 28 ? PetalIndex(dx, dy)
            : null;
        if (value == Hovered) return;
        Hovered = value;
        Changed?.Invoke();
    }

    public void ClearHover()
    {
        if (Hovered is null) return;
        Hovered = null;
        Changed?.Invoke();
    }

    /// <summary>Petal 0 sits at 12 o'clock, then clockwise.</summary>
    public static int PetalIndex(double dx, double dy)
    {
        var degrees = (Math.Atan2(dy, dx) * 180 / Math.PI + 90 + 22.5) % 360;
        if (degrees < 0) degrees += 360;
        return (int)(degrees / 45) % PetalCount;
    }

    public static double CenterAngle(int index) => -90 + index * 45;
}
