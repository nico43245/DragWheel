using System.Runtime.InteropServices;
using System.Windows.Threading;
using DragWheel.Core;
using static DragWheel.Native;

namespace DragWheel;

/// <summary>
/// Watches for "the left button is dragging something and Shift went down" and summons the wheel.
/// Low-level hooks only look at the mouse position/buttons and at three keys (Shift, Tab, Esc);
/// nothing typed is read, stored or sent anywhere.
/// </summary>
internal sealed class GlobalHooks : IDisposable
{
    // Windows where file drags start: File Explorer and the desktop.
    private static readonly HashSet<string> FileWindows = ["CabinetWClass", "ExploreWClass", "Progman", "WorkerW"];

    private readonly HookProc _mouseProc;
    private readonly HookProc _keyboardProc;
    private IntPtr _mouseHook, _keyboardHook;
    private readonly Dispatcher _ui = Dispatcher.CurrentDispatcher;

    private bool _buttonDown, _dragging, _shiftDown, _startedInFileWindow;
    private POINT _downAt;

    public GlobalHooks()
    {
        // Keep the delegates alive for as long as the hooks are installed.
        _mouseProc = MouseHook;
        _keyboardProc = KeyboardHook;
    }

    public void Start()
    {
        var module = GetModuleHandle(null);
        _mouseHook = SetWindowsHookEx(WH_MOUSE_LL, _mouseProc, module, 0);
        _keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, module, 0);
        if (_mouseHook == IntPtr.Zero || _keyboardHook == IntPtr.Zero)
            Toast.ShowError($"Couldn't watch for drags (error {Marshal.GetLastWin32Error()}). Try restarting DragWheel.");
    }

    public void Dispose()
    {
        if (_mouseHook != IntPtr.Zero) UnhookWindowsHookEx(_mouseHook);
        if (_keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(_keyboardHook);
        _mouseHook = _keyboardHook = IntPtr.Zero;
    }

    private static WheelWindow Wheel => WheelWindow.Instance;

    // Hooks must return fast: anything heavier is posted to the UI thread.
    private IntPtr MouseHook(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var info = Marshal.PtrToStructure<MSLLHOOKSTRUCT>(lParam);
            switch ((int)wParam)
            {
                case WM_LBUTTONDOWN:
                    _buttonDown = true;
                    _dragging = false;
                    _downAt = info.pt;
                    _startedInFileWindow = FileWindows.Contains(ClassNameAt(info.pt));
                    break;

                case WM_MOUSEMOVE when _buttonDown && !_dragging:
                    if (Math.Abs(info.pt.X - _downAt.X) > GetSystemMetrics(SM_CXDRAG) * 2 ||
                        Math.Abs(info.pt.Y - _downAt.Y) > GetSystemMetrics(SM_CYDRAG) * 2)
                    {
                        _dragging = true;
                        if (IsDown(VK_SHIFT)) _ui.BeginInvoke(() => Summon(IsDown(VK_MENU)));
                    }
                    break;

                case WM_LBUTTONUP:
                    _buttonDown = _dragging = false;
                    _ui.BeginInvoke(() => Wheel.HideSoon());
                    break;

                case WM_MOUSEWHEEL when Wheel.IsShowing:
                    var delta = (short)(info.mouseData >> 16);
                    _ui.BeginInvoke(() => Wheel.State.SwitchPage(delta > 0 ? -1 : 1));
                    return 1;   // don't scroll the window underneath while choosing
            }
        }
        return CallNextHookEx(_mouseHook, code, wParam, lParam);
    }

    private IntPtr KeyboardHook(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var vk = (int)Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam).vkCode;
            var down = (int)wParam is WM_KEYDOWN or WM_SYSKEYDOWN;
            var up = (int)wParam is WM_KEYUP or WM_SYSKEYUP;

            if (vk is VK_SHIFT or VK_LSHIFT or VK_RSHIFT)
            {
                if (down && !_shiftDown)
                {
                    _shiftDown = true;
                    if (Wheel.IsShowing) _ui.BeginInvoke(() => Wheel.State.SwitchPage(1));   // tap Shift again to cycle
                    else if (_buttonDown && _dragging) _ui.BeginInvoke(() => Summon(IsDown(VK_MENU)));
                }
                else if (up) _shiftDown = false;
            }
            else if (down && Wheel.IsShowing && vk is VK_TAB or VK_ESCAPE)
            {
                if (vk == VK_TAB) _ui.BeginInvoke(() => Wheel.State.SwitchPage(IsDown(VK_SHIFT) ? -1 : 1));
                else _ui.BeginInvoke(() => Wheel.HideNow());
                return 1;   // swallow: these keys belong to the wheel while it is open
            }
        }
        return CallNextHookEx(_keyboardHook, code, wParam, lParam);
    }

    private void Summon(bool toolsPage)
    {
        if (Wheel.IsShowing || !_buttonDown) return;
        if (!_startedInFileWindow && !Settings.Current.WheelInAnyApp) return;
        Wheel.ShowAtCursor(toolsPage);
    }
}
