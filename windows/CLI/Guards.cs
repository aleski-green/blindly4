using System.Text;

namespace Blindly;

internal static class Guards
{
    const string Directionality = "\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069";
    internal static string Normalize(string text) => new(text.Normalize(NormalizationForm.FormC).Where(c => !Directionality.Contains(c)).ToArray());
    internal static bool Exact(string actual, string expected) => Normalize(actual) == Normalize(expected);
    internal static int[] Path(string path)
    {
        if (path.Length == 0) return [];
        var pieces = path.Split('.');
        if (pieces.Length > 64 || pieces.Any(p => p.Length == 0 || p.Any(c => c < '0' || c > '9') || !int.TryParse(p, out _)))
            throw new CliError("Path must contain nonnegative child indexes separated by dots");
        return pieces.Select(int.Parse).ToArray();
    }
    internal static void Url(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var url) || !new[] { "http", "https", "slack" }.Contains(url.Scheme) || string.IsNullOrEmpty(url.Host))
            throw new CliError("Only absolute HTTP, HTTPS or Slack URLs are supported");
    }
    internal static void Draft(bool writable, bool focused, bool exact, bool frontmost)
    {
        if (!writable || !focused || !exact || !frontmost)
            throw CliError.Access("Input blocked: writable target, keyboard focus, exact draft and foreground PID must all match. Do not send.");
    }
}
