using System.Windows.Automation;

namespace Blindly;

internal sealed class Desktop
{
    readonly Node root;
    internal Desktop(int pid)
    {
        if (pid <= 0 || !Native.Windows().Any(w => w.Pid == pid)) throw CliError.Access($"No visible windows for PID {pid}");
        root = new Node(null, pid);
    }
    internal Node Resolve(string path)
    {
        var node = root;
        foreach (int index in Guards.Path(path))
            node = node.Children().Skip(index).FirstOrDefault() ?? throw CliError.Access($"Path {path} no longer exists; rediscover the target");
        return node;
    }
    internal IEnumerable<(Node Node, string Path)> Walk(int depth)
    {
        return Visit(root, "", depth);
        static IEnumerable<(Node, string)> Visit(Node n, string path, int remaining)
        {
            yield return (n, path);
            if (remaining == 0) yield break;
            int index = 0;
            foreach (var child in n.Children())
            {
                string next = path.Length == 0 ? $"{index}" : $"{path}.{index}";
                foreach (var row in Visit(child, next, remaining - 1)) yield return row;
                index++;
            }
        }
    }
    internal static void Tree(Invocation i)
    {
        var desktop = new Desktop(i.Pid);
        int remaining = i.Integer("max-nodes", 250, 1, 10000);
        int depth = i.Integer("depth", 4, 0, 64);
        bool truncated = false;
        Dictionary<string, object?> Build(Node n, int d)
        {
            remaining--;
            var row = n.Detail();
            var children = new List<object>();
            foreach (var child in n.Children())
            {
                if (remaining == 0 || d == 0) { truncated = true; break; }
                children.Add(Build(child, d - 1));
            }
            if (children.Count > 0) row["children"] = children;
            return row;
        }
        var tree = Build(desktop.root, depth);
        Program.Json(new { tree, truncated });
    }
    internal static void Show(Invocation i)
    {
        int count = 0;
        foreach (var (node, path) in new Desktop(i.Pid).Walk(i.Integer("depth", 4, 0, 64)))
        {
            if (++count > 10000) { Console.WriteLine("[truncated: 10000 nodes]"); break; }
            var row = node.Detail();
            Console.WriteLine($"{path,-18} {row["role"]} {row.GetValueOrDefault("title")} {row.GetValueOrDefault("value")}");
        }
    }
    internal static void Find(Invocation i)
    {
        string[] filters = ["title", "role", "value", "description"];
        if (!filters.Any(i.Has)) throw new CliError("find requires --title, --role, --value or --description");
        int limit = i.Integer("limit", 25, 1, 10000), visited = 0;
        var matches = new List<object>();
        bool truncated = false;
        foreach (var (node, path) in new Desktop(i.Pid).Walk(i.Integer("depth", 8, 0, 64)))
        {
            if (++visited > 10000) { truncated = true; break; }
            var row = node.Detail(path);
            if (filters.Where(i.Has).All(k => (row.GetValueOrDefault(k)?.ToString() ?? "").Contains(i.Value(k), StringComparison.OrdinalIgnoreCase))) matches.Add(row);
            if (matches.Count >= limit) { truncated = true; break; }
        }
        Program.Json(new { matches, truncated });
    }
    internal static void Focused(Invocation i)
    {
        var focused = AutomationElement.FocusedElement;
        if (focused == null || (i.Has("pid") && Native.ForegroundPid != i.Pid))
            throw new CliError("No focused control in the requested application", 77, "focus_unavailable");
        Program.Json(new Node(focused, i.Pid).Detail());
    }
    internal static void Mutate(Invocation i, string action, Action<Node> mutate)
    {
        var path = i.Value("path");
        var target = new Desktop(i.Pid).Resolve(path);
        mutate(target);
        Program.Json(new { path, action, ok = true });
    }
    internal static void Press(Invocation i)
    {
        i.Pair("require-value-path", "require-value");
        var desktop = new Desktop(i.Pid);
        var path = i.Value("path");
        var target = desktop.Resolve(path);
        if (i.Has("expect-description") && !(target.Detail()["description"]?.ToString() ?? "").Contains(i.Value("expect-description"), StringComparison.OrdinalIgnoreCase))
            throw new CliError("press target does not match --expect-description");
        if (i.Has("require-value-path") && !desktop.Resolve(i.Value("require-value-path")).ExactDraft(i.Value("require-value")))
            throw CliError.Access("Press blocked: the draft does not exactly match --require-value");
        target.Press();
        if (i.Has("require-selected"))
        {
            for (int attempt = 0; attempt < 20 && !target.Selected; attempt++) Thread.Sleep(50);
            if (!target.Selected) throw CliError.Access("Press completed but target was not selected; do not continue");
        }
        var result = new Dictionary<string, object?> { ["path"] = path, ["action"] = "AXPress", ["ok"] = true };
        if (i.Has("require-selected")) result["selected"] = true;
        if (i.Has("require-value-path")) result["verified"] = true;
        Program.Json(result);
    }
}
