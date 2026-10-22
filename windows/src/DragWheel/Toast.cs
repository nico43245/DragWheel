using System.Media;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using DragWheel.Core;
using Microsoft.VisualBasic.FileIO;

namespace DragWheel;

/// <summary>A small notification in the corner of the screen with Open / Show in folder / Undo.</summary>
public static class Toast
{
    private static Window? _current;

    public static void ShowError(string message)
    {
        if (Settings.Current.PlaySound) SystemSounds.Hand.Play();
        Show("DragWheel couldn't do that", message, null, isError: true);
    }

    public static void Show(string title, string body, IReadOnlyList<string>? outputs, bool isError = false)
    {
        Application.Current.Dispatcher.Invoke(() =>
        {
            _current?.Close();
            var theme = Theme.Current;
            var fg = (theme.IsDark ? Colors.White : theme.Text).Brush();

            var panel = new StackPanel { Margin = new Thickness(16, 12, 16, 12) };
            panel.Children.Add(new TextBlock
            {
                Text = title, FontWeight = FontWeights.SemiBold, FontSize = 14, Foreground = isError ? Brushes.IndianRed : fg,
                TextTrimming = TextTrimming.CharacterEllipsis,
            });
            panel.Children.Add(new TextBlock { Text = body, FontSize = 12, Foreground = fg, Opacity = 0.85, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0) });

            var window = new Window
            {
                WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
                ShowInTaskbar = false, Topmost = true, ShowActivated = false, SizeToContent = SizeToContent.Height,
                Width = 360, ResizeMode = ResizeMode.NoResize,
                Content = new Border
                {
                    Child = panel, CornerRadius = new CornerRadius(12), Background = theme.Glass.Brush(),
                    BorderBrush = theme.Accent.Brush(0.5), BorderThickness = new Thickness(1),
                    Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Opacity = 0.3 },
                    Margin = new Thickness(10),
                },
            };

            if (outputs is { Count: > 0 })
            {
                var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
                Button Add(string text, Action action)
                {
                    var b = new Button { Content = text, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(10, 3, 10, 3) };
                    b.Click += (_, _) => { action(); window.Close(); };
                    buttons.Children.Add(b);
                    return b;
                }
                Add("Open", () => outputs.ToList().ForEach(p => ProcessRunner.Shell(p)));
                Add("Show in folder", () => ProcessRunner.RevealInExplorer(outputs[0]));
                Add("Undo", () => outputs.ToList().ForEach(MoveToRecycleBin));
                panel.Children.Add(buttons);
            }

            var area = SystemParameters.WorkArea;
            window.Loaded += (_, _) =>
            {
                window.Left = area.Right - window.ActualWidth - 8;
                window.Top = area.Bottom - window.ActualHeight - 8;
            };
            var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(isError ? 9 : 7) };
            timer.Tick += (_, _) => { timer.Stop(); if (!window.IsMouseOver) window.Close(); else timer.Start(); };
            window.Closed += (_, _) => { timer.Stop(); if (_current == window) _current = null; };
            window.MouseLeftButtonUp += (_, e) => { if (e.OriginalSource is not Button) window.Close(); };

            _current = window;
            window.Show();
            timer.Start();
        });
    }

    /// <summary>Undo never deletes: the file goes to the Recycle Bin.</summary>
    private static void MoveToRecycleBin(string path)
    {
        try
        {
            if (Directory.Exists(path))
                FileSystem.DeleteDirectory(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);
            else if (File.Exists(path))
                FileSystem.DeleteFile(path, UIOption.OnlyErrorDialogs, RecycleOption.SendToRecycleBin);
        }
        catch (Exception e) when (e is IOException or OperationCanceledException or UnauthorizedAccessException) { }
    }
}
