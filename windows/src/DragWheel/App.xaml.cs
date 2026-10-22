using System.Windows;
using DragWheel.Core;

namespace DragWheel;

public partial class App : Application
{
    private Mutex? _singleInstance;
    private TrayIcon? _tray;
    private GlobalHooks? _hooks;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Scriptable mode: DragWheel.exe --run <action> <file>…
        if (e.Args.Length >= 3 && e.Args[0] == "--run")
        {
            Shutdown(await Cli.RunAsync(e.Args));
            return;
        }

        _singleInstance = new Mutex(true, $"DragWheel-{Environment.UserName}", out var isFirst);
        if (!isFirst)
        {
            MessageBox.Show("DragWheel is already running — look for its icon in the taskbar's notification area.",
                            "DragWheel", MessageBoxButton.OK, MessageBoxImage.Information);
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            Toast.ShowError($"Something went wrong: {args.Exception.Message}");
            args.Handled = true;
        };

        _tray = new TrayIcon();
        _hooks = new GlobalHooks();
        _hooks.Start();

        if (!e.Args.Contains("--background") && !Settings.Current.WelcomeShown)
        {
            Settings.Current.WelcomeShown = true;
            Settings.Current.Save();
            Toast.Show("DragWheel is running",
                       "Drag a file in File Explorer, then press Shift to open the wheel.", null);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _hooks?.Dispose();
        _tray?.Dispose();
        _singleInstance?.Dispose();
        base.OnExit(e);
    }
}
