using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Windows.Automation;

namespace Blindly;

internal static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        if (args.SequenceEqual(new[] { "--test-app" })) { SelfTest.TestApp(); return 0; }
        var clock = Stopwatch.StartNew();
        bool profile = args.Contains("--profile");
        using var deadline = new System.Threading.Timer(_ => {
            Json(new { error = "Accessibility command timed out; inspect the target before retrying input.", code = "accessibility_error" });
            Environment.Exit(77);
        }, null, 25000, Timeout.Infinite);
        try
        {
            args = args.Where(a => a != "--profile").ToArray();
            if (args.SequenceEqual(new[] { "--self-test" })) return SelfTest.Run();
            if (args.SequenceEqual(new[] { "--integration-test" })) { deadline.Change(Timeout.Infinite, Timeout.Infinite); return SelfTest.Integration(); }
            if (args.Length == 0 || args.SequenceEqual(new[] { "--help" }) || args.SequenceEqual(new[] { "help" }))
            { Console.WriteLine(Registry.Help()); return 0; }
            var command = Registry.Get(args[0]);
            if (args.Skip(1).SequenceEqual(new[] { "--help" }))
            { Json(command.Metadata); return 0; }
            var invocation = new Invocation(command, args.Skip(1).ToArray());
            command.Execute(invocation);
            return 0;
        }
        catch (CliError e) { Json(new { error = e.Message, code = e.Code }); return e.ExitCode; }
        catch (Exception e) when (e is ElementNotAvailableException or ElementNotEnabledException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException or InvalidOperationException)
        { Json(new { error = e.Message, code = "accessibility_error" }); return 77; }
        catch (Exception e) { Json(new { error = e.Message, code = "unexpected_error" }); return 1; }
        finally { if (profile) Console.Error.WriteLine(JsonSerializer.Serialize(new { elapsedMs = clock.ElapsedMilliseconds, platform = "windows" })); }
    }
    internal static void Json(object value) => Console.WriteLine(JsonSerializer.Serialize(value));
}
