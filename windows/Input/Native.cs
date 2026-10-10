using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Blindly;

internal static class Native
{
    internal sealed record Window(nint Handle, int Pid, string Title);
    delegate bool EnumWindow(nint handle, nint param);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindow callback, nint param);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(nint handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(nint handle, StringBuilder text, int length);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(nint handle, out int pid);
    [DllImport("user32.dll")] static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(nint handle);
    [DllImport("user32.dll")] static extern bool ShowWindow(nint handle, int command);
    [DllImport("user32.dll")] static extern bool IsIconic(nint handle);
    [DllImport("user32.dll")] static extern nint WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern nint GetAncestor(nint handle, uint flags);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [DllImport("user32.dll")] internal static extern uint GetClipboardSequenceNumber();
    [StructLayout(LayoutKind.Sequential)] internal struct Point { internal int X, Y; }
    [StructLayout(LayoutKind.Sequential)] internal struct INPUT { internal uint type; internal Union data; }
    [StructLayout(LayoutKind.Explicit)] internal struct Union { [FieldOffset(0)] internal MOUSEINPUT mouse; [FieldOffset(0)] internal KEYBDINPUT keyboard; }
    [StructLayout(LayoutKind.Sequential)] internal struct MOUSEINPUT { internal int x, y; internal uint data, flags, time; internal nuint extra; }
    [StructLayout(LayoutKind.Sequential)] internal struct KEYBDINPUT { internal ushort key, scan; internal uint flags, time; internal nuint extra; }
    internal static int ForegroundPid { get { GetWindowThreadProcessId(GetForegroundWindow(), out int pid); return pid; } }
    internal static List<Window> Windows()
    {
        var result = new List<Window>();
        EnumWindows((handle, _) => {
            if (IsWindowVisible(handle))
            {
                var title = new StringBuilder(1024);
                GetWindowText(handle, title, title.Capacity);
                GetWindowThreadProcessId(handle, out int pid);
                if (pid > 0 && title.Length > 0) result.Add(new Window(handle, pid, title.ToString()));
            }
            return true;
        }, 0);
        // Stable within an unchanged desktop; foreground z-order must not reorder paths.
        return result.OrderBy(w => w.Handle.ToInt64()).ToList();
    }
    internal static string ProcessName(int pid) { try { return Process.GetProcessById(pid).ProcessName; } catch (ArgumentException) { return ""; } }
    internal static object[] Apps() => Windows().GroupBy(w => w.Pid).Select(g => (object)new { pid = g.Key, name = ProcessName(g.Key), bundleIdentifier = (string?)null, frontmost = g.Key == ForegroundPid, windows = g.Select(w => w.Title).ToArray() }).ToArray();
    internal static void Activate(int pid)
    {
        if (ForegroundPid == pid) return;
        var window = Windows().FirstOrDefault(w => w.Pid == pid) ?? throw CliError.Access($"No visible window for PID {pid}");
        if (IsIconic(window.Handle)) ShowWindow(window.Handle, 9);
        SetForegroundWindow(window.Handle);
        for (int attempt = 0; attempt < 20 && ForegroundPid != pid; attempt++) Thread.Sleep(25);
        RequireForeground(pid);
    }
    internal static void RequireForeground(int pid)
    {
        if (pid <= 0 || ForegroundPid != pid) throw CliError.Access("Input blocked: the intended PID is not the foreground application");
    }
    internal static void RequirePoint(int pid, int x, int y)
    {
        var handle = GetAncestor(WindowFromPoint(new Point { X = x, Y = y }), 2);
        GetWindowThreadProcessId(handle, out int underPoint);
        if (underPoint != pid) throw CliError.Access("Input blocked: the screen point belongs to a different application");
    }
    internal static void Send(int pid, params INPUT[] inputs)
    {
        RequireForeground(pid);
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>()) != inputs.Length)
            throw CliError.Access("Windows rejected input (possibly an elevated or secure window). Inspect the target before retrying.");
    }
    internal static INPUT KeyEvent(ushort key, bool up = false, bool unicode = false) => new() { type = 1, data = new Union { keyboard = new KEYBDINPUT { key = unicode ? (ushort)0 : key, scan = unicode ? key : (ushort)0, flags = (up ? 2u : 0u) | (unicode ? 4u : 0u) } } };
    internal static void Text(int pid, string text)
    {
        foreach (char c in text) Send(pid, KeyEvent(c, unicode: true), KeyEvent(c, up: true, unicode: true));
    }
    internal static void Click(int pid, int x, int y)
    {
        RequireForeground(pid); RequirePoint(pid, x, y);
        if (!SetCursorPos(x, y)) throw CliError.Access("Cannot move the mouse to target");
        RequirePoint(pid, x, y);
        Send(pid, Mouse(2), Mouse(4));
    }
    static INPUT Mouse(uint flags, uint data = 0) => new() { type = 0, data = new Union { mouse = new MOUSEINPUT { flags = flags, data = data } } };
    internal static void Scroll(int pid, string direction, int amount)
    {
        if (!GetCursorPos(out var point)) throw CliError.Access("Cannot read mouse position");
        RequirePoint(pid, point.X, point.Y);
        int delta = amount * 120 * (direction is "down" or "left" ? -1 : 1);
        Send(pid, Mouse(direction is "left" or "right" ? 0x1000u : 0x800u, unchecked((uint)delta)));
    }
    internal static ushort[] ParseKey(string text)
    {
        var parts = text.ToLowerInvariant().Split('+');
        var keys = new List<ushort>();
        foreach (var modifier in parts[..^1]) keys.Add(modifier switch { "ctrl" or "control" or "command" or "cmd" => 0x11, "shift" => 0x10, "alt" or "option" => 0x12, _ => throw new CliError($"Unsupported modifier: {modifier}") });
        var key = parts[^1];
        ushort value = key switch {
            "return" or "enter" => 0x0d, "tab" => 9, "escape" or "esc" => 0x1b, "space" => 0x20,
            "delete" or "backspace" => 8, "forward-delete" => 0x2e, "up" => 0x26, "down" => 0x28,
            "left" => 0x25, "right" => 0x27, "home" => 0x24, "end" => 0x23, "pageup" => 0x21, "pagedown" => 0x22,
            _ when key.Length == 1 && char.IsAsciiLetterOrDigit(key[0]) => char.ToUpperInvariant(key[0]),
            _ when key.StartsWith('f') && int.TryParse(key[1..], out int f) && f >= 1 && f <= 24 => (ushort)(0x70 + f - 1),
            _ => throw new CliError($"Unsupported key: {key}")
        };
        keys.Add(value);
        return keys.ToArray();
    }
    internal static void Key(int pid, ushort[] keys) => Send(pid, keys.Select(k => KeyEvent(k)).Concat(keys.Reverse().Select(k => KeyEvent(k, up: true))).ToArray());
}
