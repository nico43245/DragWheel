using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using DragWheel.Core;
using static DragWheel.Native;

namespace DragWheel;

/// <summary>A borderless, transparent, never-activated window that floats under the cursor and accepts the drop.</summary>
public sealed class WheelWindow : Window
{
    public static WheelWindow Instance { get; } = new();

    public WheelState State { get; } = new();
    private readonly Canvas _canvas = new() { Width = WheelState.Size, Height = WheelState.Size };
    private readonly DispatcherTimer _hideTimer = new() { Interval = TimeSpan.FromMilliseconds(180) };
    private static readonly FontFamily IconFont = new("Segoe Fluent Icons, Segoe MDL2 Assets");
    private static readonly FontFamily TextFont = new("Segoe UI Variable Display, Segoe UI");

    private WheelWindow()
    {
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        AllowDrop = true;
        Width = Height = WheelState.Size;
        Content = _canvas;
        Title = "DragWheel";

        State.Changed += Render;
        Settings.Current.Changed += Render;
        _hideTimer.Tick += (_, _) => { _hideTimer.Stop(); HideNow(); };

        DragEnter += (_, e) => { State.SetFiles(FilesOf(e.Data)); Track(e); };
        DragOver += (_, e) => Track(e);
        DragLeave += (_, _) => State.ClearHover();
        Drop += OnDrop;
        MouseWheel += (_, e) => State.SwitchPage(e.Delta > 0 ? -1 : 1);

        SourceInitialized += (_, _) =>
        {
            // Tool window that never takes focus away from File Explorer.
            var hwnd = new WindowInteropHelper(this).Handle;
            var ex = (long)GetWindowLongPtr(hwnd, GWL_EXSTYLE);
            SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(ex | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST));
        };
    }

    public bool IsShowing => IsVisible && Opacity > 0;

    public void ShowAtCursor(bool toolsPage)
    {
        _hideTimer.Stop();
        State.Reset([], toolsPage);
        Opacity = 0;
        Show();

        // Place in physical pixels so it lands right under the cursor on any monitor/DPI, kept on screen.
        var hwnd = new WindowInteropHelper(this).Handle;
        GetCursorPos(out var cursor);
        var size = (int)Math.Round(WheelState.Size * GetDpiForWindow(hwnd) / 96.0);
        var info = new MONITORINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(MonitorFromPoint(cursor, 2 /* nearest */), ref info);
        var x = Math.Clamp(cursor.X - size / 2, info.rcWork.Left, Math.Max(info.rcWork.Left, info.rcWork.Right - size));
        var y = Math.Clamp(cursor.Y - size / 2, info.rcWork.Top, Math.Max(info.rcWork.Top, info.rcWork.Bottom - size));
        SetWindowPos(hwnd, HWND_TOPMOST, x, y, size, size, SWP_NOACTIVATE | SWP_SHOWWINDOW);

        BeginAnimation(OpacityProperty, new System.Windows.Media.Animation.DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(120)));
    }

    /// <summary>After the mouse button goes up: give the drop a moment to land first.</summary>
    public void HideSoon()
    {
        if (IsVisible) _hideTimer.Start();
    }

    public void HideNow()
    {
        _hideTimer.Stop();
        BeginAnimation(OpacityProperty, null);
        Opacity = 0;
        Hide();
        State.ClearHover();
    }

    private void Track(DragEventArgs e)
    {
        // Always a copy: the original file is never moved or deleted, even if Shift means "move" to Explorer.
        e.Effects = DragDropEffects.Copy;
        e.Handled = true;
        var p = e.GetPosition(this);
        State.UpdateHover(p.X, p.Y);
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        e.Effects = DragDropEffects.Copy;
        e.Handled = true;
        var files = FilesOf(e.Data);
        if (files.Count == 0) files = State.Files;
        var action = State.HoveredAction;
        HideNow();
        if (action is null || files.Count == 0) return;
        _ = Runner.RunAsync(action.Id, files);
    }

    private static IReadOnlyList<string> FilesOf(IDataObject data) =>
        data.GetDataPresent(DataFormats.FileDrop) && data.GetData(DataFormats.FileDrop) is string[] files
            ? files.Where(File.Exists).ToArray()
            : [];

    // MARK: Drawing

    private void Render()
    {
        var theme = Theme.Current;
        _canvas.Children.Clear();
        const double size = WheelState.Size, outer = WheelState.OuterRadius;
        var center = new Point(size / 2, size / 2);

        // Glass disc
        var disc = new Ellipse
        {
            Width = outer * 2 + 24, Height = outer * 2 + 24,
            Fill = theme.Glass.Brush(),
            Stroke = theme.Accent.Brush(0.35), StrokeThickness = 1,
            Effect = new DropShadowEffect { BlurRadius = 24, ShadowDepth = 6, Opacity = 0.3 },
        };
        Place(disc, center.X - disc.Width / 2, center.Y - disc.Height / 2);

        for (var i = 0; i < WheelState.PetalCount; i++) DrawPetal(i, theme, center);
        DrawCenter(theme, center);

        // Page title and dots
        var title = Pill(State.Page.Title, theme, 11, FontWeights.Heavy);
        title.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Place(title, (size - title.DesiredSize.Width) / 2, 4);

        var dots = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var page in Catalog.Pages)
        {
            var current = page.Index == State.PageIndex;
            dots.Children.Add(new Rectangle
            {
                Width = current ? 18 : 6, Height = 6, RadiusX = 3, RadiusY = 3, Margin = new Thickness(3, 0, 3, 0),
                Fill = current ? theme.Accent.Brush() : Brushes.Gray,
            });
        }
        var dotsBox = new Border { Child = dots, Padding = new Thickness(6), CornerRadius = new CornerRadius(9), Background = theme.Glass.Brush() };
        dotsBox.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Place(dotsBox, (size - dotsBox.DesiredSize.Width) / 2, size - dotsBox.DesiredSize.Height - 6);
    }

    private void DrawPetal(int index, Theme theme, Point c)
    {
        var action = State.Page.Petals[index];
        var hovered = State.Hovered == index;
        var angle = WheelState.CenterAngle(index);
        var grow = hovered ? 6 : 0;

        var petal = new System.Windows.Shapes.Path
        {
            Data = Sector(c, WheelState.InnerRadius, WheelState.OuterRadius + grow, angle - 22.5 + 2.6, angle + 22.5 - 2.6),
            Fill = hovered ? theme.Accent.Brush() : theme.Petal.Brush(),
            Stroke = theme.Accent.Brush(hovered ? 0 : 0.2),
            StrokeThickness = 1,
            Effect = hovered ? new DropShadowEffect { Color = theme.Accent, BlurRadius = 18, ShadowDepth = 0, Opacity = 0.7 } : null,
        };
        _canvas.Children.Add(petal);

        var mid = (WheelState.InnerRadius + WheelState.OuterRadius) / 2;
        var rad = angle * Math.PI / 180;
        var label = new StackPanel { Width = 80 };
        var color = (hovered ? theme.TextOnAccent : theme.Text).Brush();
        label.Children.Add(new TextBlock { Text = action.Glyph, FontFamily = IconFont, FontSize = 18, Foreground = color, HorizontalAlignment = HorizontalAlignment.Center });
        label.Children.Add(new TextBlock { Text = action.Title, FontFamily = TextFont, FontSize = 11, FontWeight = FontWeights.Bold, Foreground = color, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 3, 0, 0) });
        label.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Place(label, c.X + Math.Cos(rad) * mid - 40, c.Y + Math.Sin(rad) * mid - label.DesiredSize.Height / 2);
    }

    private void DrawCenter(Theme theme, Point c)
    {
        var hovered = State.Hovered == WheelState.CenterIndex;
        var r = WheelState.CenterRadius + (hovered ? 3 : 0);
        var hub = new Ellipse
        {
            Width = r * 2, Height = r * 2,
            Fill = hovered ? theme.Accent.Brush() : theme.Petal.Brush(),
            Stroke = theme.Accent.Brush(0.5), StrokeThickness = 1.5,
            Effect = hovered ? new DropShadowEffect { Color = theme.Accent, BlurRadius = 18, ShadowDepth = 0, Opacity = 0.7 } : null,
        };
        Place(hub, c.X - r, c.Y - r);

        var stack = new StackPanel { Width = WheelState.CenterRadius * 1.7 };
        void Line(string text, double size, FontWeight weight, Brush brush, FontFamily? font = null) =>
            stack.Children.Add(new TextBlock
            {
                Text = text, FontSize = size, FontWeight = weight, Foreground = brush, FontFamily = font ?? TextFont,
                TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, HorizontalAlignment = HorizontalAlignment.Center,
            });

        if (State.HoveredAction is { } a && !hovered)
        {
            Line(a.Title, 13, FontWeights.Heavy, theme.Accent.Brush());
            Line(a.Hint, 10, FontWeights.Medium, theme.Text.Brush());
        }
        else
        {
            var center = State.Page.Center;
            var brush = (hovered ? theme.TextOnAccent : theme.Text).Brush();
            Line(center.Glyph, 18, FontWeights.Normal, brush, IconFont);
            Line(State.Files.Count > 1 ? $"{State.Files.Count} files · {center.Title}" : center.Title, 11, FontWeights.Heavy, brush);
            if (hovered) Line(center.Hint, 9, FontWeights.Medium, brush);
        }
        stack.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Place(stack, c.X - stack.Width / 2, c.Y - stack.DesiredSize.Height / 2);
    }

    private static Border Pill(string text, Theme theme, double size, FontWeight weight) => new()
    {
        Child = new TextBlock { Text = text, FontSize = size, FontWeight = weight, FontFamily = TextFont, Foreground = (theme.IsDark ? Colors.White : theme.Text).Brush() },
        Padding = new Thickness(12, 4, 12, 5),
        CornerRadius = new CornerRadius(12),
        Background = theme.Glass.Brush(),
        BorderBrush = theme.Accent.Brush(0.4),
        BorderThickness = new Thickness(1),
    };

    private static Geometry Sector(Point c, double inner, double outer, double startDeg, double endDeg)
    {
        Point At(double r, double deg) => new(c.X + r * Math.Cos(deg * Math.PI / 180), c.Y + r * Math.Sin(deg * Math.PI / 180));
        var figure = new PathFigure { StartPoint = At(outer, startDeg), IsClosed = true };
        figure.Segments.Add(new ArcSegment(At(outer, endDeg), new Size(outer, outer), 0, false, SweepDirection.Clockwise, true));
        figure.Segments.Add(new LineSegment(At(inner, endDeg), true));
        figure.Segments.Add(new ArcSegment(At(inner, startDeg), new Size(inner, inner), 0, false, SweepDirection.Counterclockwise, true));
        var g = new PathGeometry([figure]);
        g.Freeze();
        return g;
    }

    private void Place(UIElement element, double x, double y)
    {
        Canvas.SetLeft(element, x);
        Canvas.SetTop(element, y);
        _canvas.Children.Add(element);
    }
}
