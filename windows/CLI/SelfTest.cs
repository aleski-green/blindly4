using System.Diagnostics;
using System.Text.Json;
using System.Windows.Forms;

namespace Blindly;

internal static class SelfTest
{
    internal static int Run()
    {
        int passed = 0;
        void Check(bool condition) { if (!condition) throw new Exception($"Self-test {passed + 1} failed"); passed++; }
        void Reject(Action action, int exit = 64) { try { action(); } catch (CliError e) { Check(e.ExitCode == exit); return; } throw new Exception("Unsafe/invalid input was accepted"); }
        Check(Registry.All.Select(c => c.Name).Distinct().Count() == Registry.All.Length);
        Check(Registry.Get("press").Risk == "external-commit"); Check(Registry.Get("key").Risk == "external-commit");
        Check(Registry.Get("tree").Risk == "read-only");
        foreach (var obsolete in new[] { "serve", "snapshot", "changes", "workflow" }) Reject(() => Registry.Get(obsolete));
        Reject(() => new Invocation(Registry.Get("tree"), ["--lease", "x"]));
        Reject(() => new Invocation(Registry.Get("tree"), ["--depth"]));
        Reject(() => new Invocation(Registry.Get("tree"), ["--depth", "2", "--depth", "3"]));
        Reject(() => new Invocation(Registry.Get("tree"), ["--depth", "-1"]).Integer("depth", 4));
        Reject(() => new Invocation(Registry.Get("click"), ["--x", "NaN"]).Number("x"));
        Check(Guards.Path("0.2.15").SequenceEqual(new[] { 0, 2, 15 })); Check(Guards.Path("").Length == 0);
        foreach (var path in new[] { "-1", "1..2", "1.", "a", "2147483648", "0. 1" }) Reject(() => Guards.Path(path));
        Check(Guards.Exact("caf\u00e9", "cafe\u0301")); Check(Guards.Exact("\u200fمرحبا", "مرحبا"));
        Check(!Guards.Exact("draft\n", "draft")); Check(!Guards.Exact("old draft", "draft")); Check(!Guards.Exact("Draft", "draft"));
        foreach (var url in new[] { "file:///C:/test", "javascript:alert(1)", "shell:AppsFolder", "relative" }) Reject(() => Guards.Url(url));
        Guards.Url("https://example.com"); passed++;
        for (int bits = 0; bits < 15; bits++) { int b = bits; Reject(() => Guards.Draft((b & 1) != 0, (b & 2) != 0, (b & 4) != 0, (b & 8) != 0), 77); }
        Guards.Draft(true, true, true, true); passed++;
        Reject(() => new Invocation(Registry.Get("key"), ["--target-path", "0", "--require-value", "draft"]).Pair("target-path", "require-value", true));
        Reject(() => new Invocation(Registry.Get("press"), ["--require-value", "draft"]).Pair("require-value-path", "require-value"));
        Check(Native.ParseKey("command+a").SequenceEqual(new ushort[] { 17, 65 }));
        Check(Native.ParseKey("enter").SequenceEqual(Native.ParseKey("return")));
        Reject(() => Native.ParseKey("ctrl+bogus")); Reject(() => Native.ParseKey("unknown+a"));
        Check(System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>() == (IntPtr.Size == 8 ? 40 : 28));
        Program.Json(new { ok = true, tests = passed, platform = "windows", suite = "permission-free" });
        return 0;
    }

    internal static void TestApp()
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        using var form = new Form { Text = "Blindly4 Windows Test Fixture", Width = 660, Height = 350, StartPosition = FormStartPosition.CenterScreen };
        var title = new Label { Text = "Local accessibility test — no external actions", Left = 20, Top = 20, Width = 590 };
        var edit = new TextBox { Name = "Draft", AccessibleName = "Draft", Multiline = true, Left = 20, Top = 55, Width = 590, Height = 110 };
        var result = new Label { Name = "Result", AccessibleName = "Result", Text = "Not submitted", Left = 20, Top = 225, Width = 590 };
        var submit = new Button { Name = "Submit", AccessibleName = "Submit test draft", Text = "Submit test draft", Left = 20, Top = 180, Width = 180 };
        submit.Click += (_, _) => { result.Text = "Submitted: " + edit.Text; result.AccessibleName = result.Text; };
        var check = new CheckBox { AccessibleName = "Test checkbox", Text = "Test checkbox", Left = 230, Top = 180, Width = 180 };
        form.Controls.AddRange([title, edit, submit, check, result]);
        form.Shown += (_, _) => edit.Focus();
        Application.Run(form);
    }

    internal static int Integration()
    {
        string exe = Environment.ProcessPath!;
        using var fixture = Process.Start(new ProcessStartInfo(exe) { ArgumentList = { "--test-app" }, UseShellExecute = false, CreateNoWindow = true })!;
        int tests = 0;
        JsonElement Run(int expected, params string[] args)
        {
            var start = new ProcessStartInfo(exe) { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true };
            foreach (var arg in args) start.ArgumentList.Add(arg);
            using var process = Process.Start(start)!;
            string stdout = process.StandardOutput.ReadToEnd(); string stderr = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != expected) throw new Exception($"{string.Join(' ', args)} exited {process.ExitCode}, expected {expected}: {stdout} {stderr}");
            tests++;
            return JsonDocument.Parse(stdout).RootElement.Clone();
        }
        void Check(bool condition, string reason) { if (!condition) throw new Exception(reason); tests++; }
        string Find(string title) => Run(0, "find", "--pid", fixture.Id.ToString(), "--title", title, "--depth", "6").GetProperty("matches")[0].GetProperty("path").GetString()!;
        try
        {
            for (int attempt = 0; attempt < 100 && !Native.Windows().Any(w => w.Pid == fixture.Id); attempt++)
            {
                if (fixture.HasExited) throw new Exception($"Fixture exited {fixture.ExitCode}");
                Thread.Sleep(100);
            }
            Thread.Sleep(300);
            string pid = fixture.Id.ToString();
            Check(Run(0, "apps").GetProperty("apps").EnumerateArray().Any(a => a.GetProperty("pid").GetInt32() == fixture.Id), "Fixture missing from apps");
            var tree = Run(0, "tree", "--pid", pid, "--depth", "5");
            Check(tree.GetProperty("tree").GetProperty("role").GetString() == "AXApplication", "Application root incompatible");
            Check(Run(0, "tree", "--pid", pid, "--max-nodes", "1").GetProperty("truncated").GetBoolean(), "Tree must report truncation");
            string draft = Find("Draft");
            Run(0, "set-value", "--pid", pid, "--path", draft, "--value", "old draft");
            Check(Run(0, "inspect", "--pid", pid, "--path", Find("Draft")).GetProperty("value").GetString() == "old draft", "ValuePattern write failed");
            Run(0, "focus", "--pid", pid, "--path", Find("Draft"));
            Check(Run(0, "focused", "--pid", pid).GetProperty("focused").GetBoolean(), "Focus missing");
            Run(0, "paste", "--pid", pid, "--target-path", Find("Draft"), "--text", "");
            Check(Run(0, "inspect", "--pid", pid, "--path", Find("Draft")).GetProperty("value").GetString() == "", "Empty guarded draft failed");
            string message = "Windows مرحبا café 🪟";
            Run(0, "paste", "--pid", pid, "--target-path", Find("Draft"), "--text", message);
            Check(Run(0, "inspect", "--pid", pid, "--path", Find("Draft")).GetProperty("value").GetString() == message, "Unicode paste failed");
            Run(77, "key", "--pid", pid, "--key", "return", "--target-path", Find("Draft"), "--require-value", "wrong draft");
            Run(77, "press", "--pid", pid, "--path", Find("Submit test draft"), "--require-value-path", Find("Draft"), "--require-value", "wrong draft");
            Run(64, "paste", "--pid", pid, "--target-path", Find("Submit test draft"), "--text", "never entered");
            Run(64, "press", "--pid", pid, "--path", Find("Submit test draft"), "--expect-description", "Wrong button");
            Run(0, "press", "--pid", pid, "--path", Find("Submit test draft"), "--expect-description", "Submit", "--require-value-path", Find("Draft"), "--require-value", message);
            Check(Run(0, "find", "--pid", pid, "--title", "Submitted: " + message).GetProperty("matches").GetArrayLength() == 1, "Guarded submission was not observed");
            Run(0, "focus", "--pid", pid, "--path", Find("Draft"));
            Run(0, "key", "--pid", pid, "--key", "ctrl+a", "--target-path", Find("Draft"), "--require-value", message);
            Run(0, "type", "--pid", pid, "--text", "Typed Unicode: مرحبا");
            Check(Run(0, "inspect", "--pid", pid, "--path", Find("Draft")).GetProperty("value").GetString() == "Typed Unicode: مرحبا", "SendInput Unicode failed");
            Run(77, "inspect", "--pid", pid, "--path", "99999");
            Run(77, "click", "--pid", pid, "--x", "-99999", "--y", "-99999");
            Program.Json(new { ok = true, tests, suite = "live Windows UI Automation + SendInput", fixturePid = fixture.Id });
            return 0;
        }
        finally { if (!fixture.HasExited) { fixture.CloseMainWindow(); if (!fixture.WaitForExit(3000)) fixture.Kill(); } }
    }
}
