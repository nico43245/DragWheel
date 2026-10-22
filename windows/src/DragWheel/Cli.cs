using System.Runtime.InteropServices;
using DragWheel.Core;

namespace DragWheel;

/// <summary><c>DragWheel.exe --run toWEBP photo.png</c> — prints each result to the console it was started from.</summary>
internal static partial class Cli
{
    public static async Task<int> RunAsync(string[] args)
    {
        AttachConsole(-1);   // the parent console, if any
        if (!Enum.TryParse<ActionId>(args[1], out var action))
        {
            Console.WriteLine($"\nUnknown action '{args[1]}'. Actions: {string.Join(' ', Enum.GetNames<ActionId>())}");
            return 2;
        }
        var failed = false;
        Console.WriteLine();
        foreach (var o in await ConversionEngine.PerformAsync(action, args[2..]))
        {
            failed |= !o.Succeeded;
            Console.WriteLine(o.Succeeded
                ? $"✓ {Path.GetFileName(o.Source)} → {o.Output ?? "(opened)"}"
                : $"✗ {Path.GetFileName(o.Source)}: {o.Error}");
        }
        return failed ? 1 : 0;
    }

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool AttachConsole(int processId);
}
