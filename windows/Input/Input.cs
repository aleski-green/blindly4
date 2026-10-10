using System.Windows.Forms;

namespace Blindly;

internal static class Input
{
    static int Target(Invocation i) { int pid = i.Pid; Native.Activate(pid); return pid; }
    internal static void Click(Invocation i)
    {
        var x = i.Number("x"); var y = i.Number("y");
        if (Math.Abs(x) > 100000 || Math.Abs(y) > 100000) throw new CliError("Screen coordinate out of range");
        int pid = Target(i); Native.Click(pid, (int)Math.Round(x), (int)Math.Round(y));
        Program.Json(new { x, y, pid, ok = true });
    }
    internal static void Type(Invocation i)
    {
        var text = i.Value("text"); int pid = Target(i); Native.Text(pid, text);
        Program.Json(new { characters = text.EnumerateRunes().Count(), pid, ok = true });
    }
    internal static void Key(Invocation i)
    {
        i.Pair("target-path", "require-value", requirePid: true);
        var key = i.Value("key"); var keys = Native.ParseKey(key); int pid = Target(i);
        if (i.Has("target-path"))
        {
            var target = new Desktop(pid).Resolve(i.Value("target-path"));
            Guards.Draft(target.Writable, target.HasFocus, target.ExactDraft(i.Value("require-value")), Native.ForegroundPid == pid);
        }
        Native.Key(pid, keys);
        var result = new Dictionary<string, object?> { ["key"] = key, ["pid"] = pid, ["ok"] = true };
        if (i.Has("target-path")) { result["targetPath"] = i.Value("target-path"); result["verified"] = true; }
        Program.Json(result);
    }
    internal static void SelectedText(Invocation i)
    {
        var value = i.Value("value"); int pid = i.Pid;
        var target = new Desktop(pid).Resolve(i.Value("path"));
        if (!target.Writable) throw new CliError("Target is not a writable text control");
        target.Focus(); Native.RequireForeground(pid);
        if (!target.HasFocus) throw CliError.Access("Target lost focus");
        Native.Text(pid, value);
        Program.Json(new { path = i.Value("path"), attribute = "AXSelectedText", ok = true });
    }
    internal static void Scroll(Invocation i)
    {
        string direction = i.Value("direction").ToLowerInvariant();
        if (!new[] { "up", "down", "left", "right" }.Contains(direction)) throw new CliError("Invalid scroll direction");
        int amount = i.Integer("amount", 3, 1, 100); int pid = Target(i);
        Native.Scroll(pid, direction, amount);
        Program.Json(new { direction, amount, pid, ok = true });
    }
    internal static void Paste(Invocation i)
    {
        string text = i.Value("text"); string? path = i.Optional("target-path");
        if (path != null && !i.Has("pid")) throw new CliError("paste --target-path requires --pid");
        int pid = i.Pid;
        Node? target = path == null ? null : new Desktop(pid).Resolve(path);
        if (target != null && !target.Writable) throw new CliError("Paste blocked: --target-path must resolve to a writable UI Automation text control");
        Native.Activate(pid);
        if (target != null)
        {
            target.SetValue("");
            if (!target.ExactDraft("")) throw CliError.Access("Paste blocked: existing draft could not be cleared");
            target.Focus();
            Guards.Draft(target.Writable, target.HasFocus, target.ExactDraft(""), Native.ForegroundPid == pid);
        }
        // Materialize each clipboard format before input; do not restore a live OLE proxy.
        var previous = Clipboard.GetDataObject();
        var backup = new DataObject();
        if (previous != null)
            foreach (var format in previous.GetFormats(false))
                if (previous.GetData(format, false) is { } data) backup.SetData(format, false, data);
        var replacement = new DataObject();
        replacement.SetData(DataFormats.UnicodeText, text);
        Clipboard.SetDataObject(replacement, true);
        uint sequence = Native.GetClipboardSequenceNumber();
        try
        {
            if (target != null) Guards.Draft(target.Writable, target.HasFocus, target.ExactDraft(""), Native.ForegroundPid == pid);
            Native.Key(pid, Native.ParseKey("ctrl+v"));
            if (target != null)
            {
                bool verified = false;
                for (int attempt = 0; attempt < 40; attempt++)
                {
                    if (target.ExactDraft(text) && target.HasFocus && Native.ForegroundPid == pid) { verified = true; break; }
                    Thread.Sleep(25);
                }
                if (!verified) throw CliError.Access("Paste failed exact draft verification; do not send or repeat input without inspecting the draft");
            }
            else Thread.Sleep(300);
        }
        finally
        {
            // Do not overwrite a clipboard change made by the user during the paste.
            if (Native.GetClipboardSequenceNumber() == sequence)
            {
                if (previous == null) Clipboard.Clear(); else Clipboard.SetDataObject(backup, true);
            }
        }
        var result = new Dictionary<string, object?> { ["characters"] = text.EnumerateRunes().Count(), ["pid"] = pid, ["ok"] = true };
        if (path != null) { result["targetPath"] = path; result["verified"] = true; }
        Program.Json(result);
    }
}
