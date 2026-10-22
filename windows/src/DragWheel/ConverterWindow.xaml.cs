using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DragWheel.Core;
using Microsoft.Win32;

namespace DragWheel;

/// <summary>The desktop window: drop or pick many files, then click an action to run it on all of them.</summary>
public partial class ConverterWindow : Window
{
    private static ConverterWindow? _open;
    private readonly List<string> _files = [];
    private int _page;

    public static void ShowSingle()
    {
        _open ??= new ConverterWindow();
        _open.Show();
        if (_open.WindowState == WindowState.Minimized) _open.WindowState = WindowState.Normal;
        _open.Activate();
    }

    public ConverterWindow()
    {
        InitializeComponent();
        RecentList.ItemsSource = Runner.History;
        Closed += (_, _) => _open = null;
        DragEnter += (_, e) => { e.Effects = DragDropEffects.Copy; DropZone.BorderBrush = Theme.Current.Accent.Brush(); };
        DragLeave += (_, _) => DropZone.BorderBrush = new SolidColorBrush(Color.FromArgb(0x88, 0x88, 0x88, 0x88));
        Drop += (_, e) =>
        {
            DropZone.BorderBrush = new SolidColorBrush(Color.FromArgb(0x88, 0x88, 0x88, 0x88));
            if (e.Data.GetData(DataFormats.FileDrop) is string[] dropped) Add(dropped.Where(File.Exists));
        };
        Refresh();
    }

    private void Add(IEnumerable<string> paths)
    {
        foreach (var p in paths)
            if (!_files.Contains(p, StringComparer.OrdinalIgnoreCase)) _files.Add(p);
        if (_files.Count > 0) _page = Catalog.BestPage(_files);
        Refresh();
    }

    private void Refresh()
    {
        var theme = Theme.Current;
        EmptyHint.Visibility = _files.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        FileListPanel.Visibility = _files.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        FileCount.Text = $"{_files.Count} file{(_files.Count == 1 ? "" : "s")}";
        FileList.ItemsSource = _files.Select(Path.GetFileName).ToList();

        PageTabs.Children.Clear();
        foreach (var page in Catalog.Pages)
        {
            var index = page.Index;
            var tab = new ToggleButton(page.Title, index == _page, theme);
            tab.Click += (_, _) => { _page = index; Refresh(); };
            PageTabs.Children.Add(tab);
        }

        var actions = Catalog.Pages[_page].All.ToList();
        if (_page == 0) actions.Add(Catalog.Bmp);
        ActionGrid.Items.Clear();
        foreach (var action in actions)
        {
            var content = new StackPanel();
            content.Children.Add(new TextBlock { Text = action.Glyph, FontFamily = (FontFamily)FindResource("IconFont"), FontSize = 18, HorizontalAlignment = HorizontalAlignment.Center });
            content.Children.Add(new TextBlock { Text = action.Title, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 3, 0, 0) });
            content.Children.Add(new TextBlock { Text = action.Hint, FontSize = 11, Opacity = 0.65, HorizontalAlignment = HorizontalAlignment.Center });
            var button = new Button { Content = content, Margin = new Thickness(5), Padding = new Thickness(6, 8, 6, 8), IsEnabled = _files.Count > 0 && Busy.Visibility != Visibility.Visible };
            var id = action.Id;
            button.Click += async (_, _) =>
            {
                Busy.Visibility = Visibility.Visible;
                Refresh();
                try { await Runner.RunAsync(id, _files.ToList()); }
                finally { Busy.Visibility = Visibility.Collapsed; Refresh(); }
            };
            ActionGrid.Items.Add(button);
        }
    }

    private void ChooseFiles(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Multiselect = true, Title = "Choose files to convert" };
        if (dialog.ShowDialog(this) == true) Add(dialog.FileNames);
    }

    private void ClearFiles(object sender, RoutedEventArgs e)
    {
        _files.Clear();
        Refresh();
    }

    private void ClearHistory(object sender, RoutedEventArgs e) => Runner.History.Clear();

    private void RevealRecent(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (RecentList.SelectedItem is HistoryItem { Output: { } output }) ProcessRunner.RevealInExplorer(output);
    }

    private sealed class ToggleButton : Button
    {
        public ToggleButton(string title, bool selected, Theme theme)
        {
            Content = title;
            Padding = new Thickness(12, 5, 12, 5);
            Margin = new Thickness(0, 0, 6, 0);
            FontWeight = selected ? FontWeights.Bold : FontWeights.Normal;
            Background = selected ? theme.Accent.Brush() : Brushes.Transparent;
            Foreground = selected ? theme.TextOnAccent.Brush() : SystemColors.ControlTextBrush;
            BorderBrush = theme.Accent.Brush(0.5);
        }
    }
}
