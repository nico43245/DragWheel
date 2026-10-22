using System.Collections.ObjectModel;
using System.Media;
using System.Windows;
using DragWheel.Core;

namespace DragWheel;

public sealed record HistoryItem(DateTime Date, string Source, string? Output, ActionId Action, string? Error)
{
    public string Title => Output is not null ? Path.GetFileName(Output) : $"{Path.GetFileName(Source)} → {Catalog.Action(Action).Title}";
    public string Detail => Error ?? (Output is not null ? Text.SizeSummary(Source, Output) : "Opened");
}

/// <summary>Runs an action, remembers it and tells the user how it went.</summary>
public static class Runner
{
    /// <summary>The 30 most recent results (UI thread only).</summary>
    public static ObservableCollection<HistoryItem> History { get; } = [];

    public static async Task<IReadOnlyList<Outcome>> RunAsync(ActionId action, IReadOnlyList<string> files)
    {
        var outcomes = await ConversionEngine.PerformAsync(action, files);
        Application.Current.Dispatcher.Invoke(() => Report(outcomes));
        return outcomes;
    }

    private static void Report(IReadOnlyList<Outcome> outcomes)
    {
        foreach (var o in outcomes)
            History.Insert(0, new HistoryItem(DateTime.Now, o.Source, o.Output, o.Action, o.Error));
        while (History.Count > 30) History.RemoveAt(History.Count - 1);

        var made = outcomes.Where(o => o.Succeeded && o.Output is not null).ToList();
        var failed = outcomes.Where(o => !o.Succeeded).ToList();

        if (made.Count > 0)
        {
            var paths = made.Select(o => o.Output!).ToList();
            var title = made.Count == 1 ? Path.GetFileName(paths[0]) : $"{made.Count} files ready";
            var body = made.Count == 1 ? Text.SizeSummary(made[0].Source, paths[0])
                                       : string.Join(", ", paths.Take(4).Select(Path.GetFileName));
            if (failed.Count > 0) body += $"\n{failed.Count} failed: {failed[0].Error}";
            Toast.Show(title, body, paths);
            if (Settings.Current.PlaySound) SystemSounds.Asterisk.Play();
            if (Settings.Current.RevealAfterConvert) ProcessRunner.RevealInExplorer(paths[0]);
        }
        else if (failed.Count > 0)
        {
            Toast.ShowError(failed.Count == 1 ? $"{Path.GetFileName(failed[0].Source)}: {failed[0].Error}"
                                              : $"{failed.Count} files failed. {failed[0].Error}");
        }
    }
}
