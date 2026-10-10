using System.Text.RegularExpressions;

namespace Blindly;

internal sealed record Command(string Name, string Arguments, string Summary, string Risk, bool Accessibility, Action<Invocation> Execute)
{
    internal string[] Options => Regex.Matches(Arguments, @"--([a-z-]+)").Select(m => m.Groups[1].Value).Distinct().Order().ToArray();
    internal object Metadata => new { name = Name, usage = $"blindly4 {Name} {Arguments}".Trim(), summary = Summary, risk = Risk, requiresAccessibility = Accessibility, options = Options };
}

internal static class Registry
{
    const string PathArgs = "--path INDEX[.INDEX...] [--pid PID]";
    static Command Read(string name, string args, string summary, Action<Invocation> action) => new(name, args, summary, "read-only", true, action);
    static Command Mutate(string name, string args, string summary, Action<Invocation> action, string risk = "ui-mutation") => new(name, args, summary, risk, true, action);
    internal static readonly Command[] All = [
        new("schema", "", "Print command metadata. Windows UIA retains AX role/action names for compatibility.", "read-only", false,
            _ => Program.Json(new { schemaVersion = 2, platform = "windows", backend = "UIAutomation", commands = All!.Select(c => c.Metadata) })),
        new("request-permission", "", "Windows UI Automation needs no macOS permission. Elevated and secure desktops remain inaccessible.", "ui-mutation", false,
            _ => Program.Json(new { trusted = true, platform = "windows", note = "Available on the current interactive desktop at the same integrity level. Does not elevate or change permissions." })),
        new("apps", "", "List visible GUI applications and PIDs.", "read-only", false, _ => Program.Json(new { apps = Native.Apps() })),
        Mutate("activate", "--pid PID", "Bring an application to the foreground and verify it.", i => { int pid = i.Integer("pid", 0, 1); if (pid == 0) throw new CliError("Missing --pid"); Native.Activate(pid); Program.Json(new { pid, ok = true }); }),
        Mutate("open", "--url URL", "Open an HTTP, HTTPS or Slack URL.", i => { var url = i.Value("url"); Guards.Url(url); System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); Program.Json(new { url, ok = true }); }),
        Read("tree", "[--pid PID] [--depth N] [--max-nodes N]", "Read a bounded live accessibility tree.", Desktop.Tree),
        Read("show", "[--pid PID] [--depth N]", "Print a readable live outline with paths.", Desktop.Show),
        Read("find", "[--title TEXT] [--role ROLE] [--value TEXT] [--description TEXT] [--pid PID] [--depth N] [--limit N]", "Search current accessible properties.", Desktop.Find),
        Read("focused", "[--pid PID]", "Read the focused control without changing focus.", Desktop.Focused),
        Read("inspect", PathArgs, "Inspect one live element.", i => Program.Json(new Desktop(i.Pid).Resolve(i.Value("path")).Detail())),
        Read("actions", PathArgs, "List supported actions.", i => Program.Json(new { path = i.Value("path"), actions = new Desktop(i.Pid).Resolve(i.Value("path")).Actions() })),
        Mutate("focus", PathArgs, "Focus an element.", i => Desktop.Mutate(i, "AXFocused", n => n.Focus())),
        Mutate("show-menu", PathArgs, "Expand an accessible menu control when supported.", i => Desktop.Mutate(i, "AXShowMenu", n => n.Expand())),
        Mutate("scroll-to", PathArgs, "Scroll an accessible item into view.", i => Desktop.Mutate(i, "AXScrollToVisible", n => n.ScrollTo())),
        Mutate("press", PathArgs + " [--expect-description TEXT] [--require-selected] [--require-value-path PATH --require-value TEXT]", "Invoke or select a control; may submit external data.", Desktop.Press, "external-commit"),
        Mutate("set-value", PathArgs + " --value TEXT", "Set a writable ValuePattern.", i => Desktop.Mutate(i, "AXValue", n => n.SetValue(i.Value("value")))),
        Mutate("set-selected-text", PathArgs + " --value TEXT", "Replace selected text in a focused writable control.", Input.SelectedText),
        Mutate("click", "--x X --y Y [--pid PID]", "Click a screen coordinate in the verified target application.", Input.Click),
        Mutate("type", "--text TEXT [--pid PID]", "Inject Unicode text into the foreground application.", Input.Type),
        Mutate("paste", "--text TEXT [--pid PID] [--target-path PATH]", "Paste, optionally verifying an exact writable target draft.", Input.Paste),
        Mutate("scroll", "--direction up|down|left|right [--amount LINES] [--pid PID]", "Inject bounded wheel input into the foreground application.", Input.Scroll),
        Mutate("key", "--key KEY [--pid PID] [--target-path PATH --require-value TEXT]", "Inject a key; a guarded key requires exact focused draft and PID.", Input.Key, "external-commit")
    ];
    internal static Command Get(string name) => All.FirstOrDefault(c => c.Name == name) ?? throw new CliError($"Unknown command: {name}");
    internal static string Help() => "Blindly4 for Windows — native UI Automation, stateless CLI\n" + string.Join("\n", All.Select(c => $"  {c.Name} {c.Arguments}\n    {c.Summary} [{c.Risk}]")) + "\nGlobal: --profile, --self-test. Paths are live: rediscover before input. Serialize desktop workflows.";
}
