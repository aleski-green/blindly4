using System.Globalization;

namespace Blindly;

internal sealed class CliError(string message, int exitCode = 64, string code = "usage_error") : Exception(message)
{
    public int ExitCode { get; } = exitCode;
    public string Code { get; } = code;
    public static CliError Access(string message) => new(message, 77, "accessibility_error");
}

internal sealed class Invocation
{
    readonly Dictionary<string, string> values = new();
    internal Invocation(Command command, string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--") || !command.Options.Contains(args[i][2..]))
                throw new CliError($"Unknown option for {command.Name}: {args[i]}");
            var key = args[i][2..];
            if (values.ContainsKey(key)) throw new CliError($"Duplicate option --{key}");
            if (key == "require-selected") { values[key] = "true"; continue; }
            if (++i >= args.Length || args[i].StartsWith("--")) throw new CliError($"Missing value for --{key}");
            values[key] = args[i];
        }
    }
    internal string? Optional(string name) => values.GetValueOrDefault(name);
    internal string Value(string name) => Optional(name) ?? throw new CliError($"Missing --{name}");
    internal bool Has(string name) => values.ContainsKey(name);
    internal int Integer(string name, int fallback, int min = 0, int max = int.MaxValue)
    {
        if (!Has(name)) return fallback;
        if (!int.TryParse(Value(name), out int n) || n < min || n > max) throw new CliError($"--{name} must be an integer from {min} to {max}");
        return n;
    }
    internal double Number(string name)
    {
        if (!double.TryParse(Value(name), NumberStyles.Float, CultureInfo.InvariantCulture, out double n) || !double.IsFinite(n))
            throw new CliError($"--{name} must be finite and numeric");
        return n;
    }
    internal int Pid => Integer("pid", Native.ForegroundPid, 1);
    internal void Pair(string a, string b, bool requirePid = false)
    {
        if (Has(a) != Has(b) || (Has(a) && requirePid && !Has("pid")))
            throw new CliError($"--{a} and --{b} must be supplied together" + (requirePid ? " with --pid" : ""));
    }
}
