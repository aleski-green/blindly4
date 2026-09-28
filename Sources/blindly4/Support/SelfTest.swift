import Foundation

/// Dependency-free checks for the generic hot path and the CLI contracts that guard
/// unsafe input. Kept in the executable so `blindly4 --self-test` validates the build
/// anywhere it can run, with no test framework and no Accessibility permission.
enum SelfTest {
    private struct Node {
        let name: String
        let children: [Node]
    }

    static func run() -> String? {
        let root = Node(name: "root", children: [
            Node(name: "first", children: [Node(name: "target", children: [])]),
            Node(name: "second", children: [Node(name: "target", children: [])])
        ])
        var visits = 0
        let first = depthFirstMatches(
            root: root, depth: 3, limit: 1,
            children: { node, _ in node.children },
            matches: { $0.name == "target" },
            onVisit: { visits += 1 }
        )
        guard first.map(\.path) == ["0.0"], visits == 3 else {
            return "bounded depth-first search did not stop after the first match"
        }
        let shallow = depthFirstMatches(
            root: root, depth: 1, limit: 2,
            children: { node, _ in node.children }, matches: { $0.name == "target" }
        )
        guard shallow.isEmpty else { return "depth limit was ignored" }
        guard sameVisibleText("\u{200E}hello\u{2069}", "hello") else {
            return "visible draft text did not ignore AX directionality markers"
        }
        guard !sameVisibleText("hello (old draft)", "hello") else {
            return "draft validation accepted text with a stale suffix"
        }
        guard !sameVisibleText("old hello", "hello") else {
            return "draft validation accepted text with a stale prefix"
        }
        guard isVisiblyEmpty("\n\u{200E}"), !isVisiblyEmpty("\nold draft") else {
            return "visible-empty validation accepted or rejected the wrong draft"
        }
        guard !CommandRegistry.requestsCommandHelp(["--text", "help"]),
              !CommandRegistry.requestsCommandHelp(["--path", "0.2", "--value", "-h"]) else {
            return "an option value was mistaken for a help request"
        }
        guard CommandRegistry.requestsCommandHelp(["help"]),
              CommandRegistry.requestsCommandHelp(["--help"]),
              CommandRegistry.requestsCommandHelp(["--path", "0.2", "--help"]) else {
            return "a help request was not recognized"
        }
        do {
            _ = try Invocation(command: "find", arguments: ["--titel", "Settings"], allowedOptions: ["title"])
            return "a misspelled option was accepted instead of rejected"
        } catch CLIError.usage(let message) where message.contains("--titel") {
            // Expected: an unknown option must fail rather than be silently dropped.
        } catch {
            return "a misspelled option did not produce a usage error"
        }
        let press = CommandRegistry.command(named: "press")
        guard press?.risk == .externalCommit, press?.optionNames.contains("require-selected") == true else {
            return "command metadata lost the risk classification or its declared options"
        }
        let scroll = CommandRegistry.command(named: "scroll")
        let scrollTo = CommandRegistry.command(named: "scroll-to")
        guard scroll?.risk == .uiMutation,
              scroll?.optionNames.isSuperset(of: ["direction", "amount", "pid"]) == true,
              scrollTo?.risk == .uiMutation,
              scrollTo?.optionNames.isSuperset(of: ["path", "pid"]) == true else {
            return "scroll command metadata or risk classification is incorrect"
        }
        guard (try? ScrollDirection(cliValue: "UP")) == .up,
              (try? ScrollDirection(cliValue: "right")) == .right else {
            return "scroll direction normalization is incorrect"
        }
        do {
            _ = try ScrollDirection(cliValue: "diagonal")
            return "an unsupported scroll direction was accepted"
        } catch CLIError.usage {
            // Expected: scrolling is limited to the four named directions.
        } catch {
            return "an unsupported scroll direction did not produce a usage error"
        }
        do {
            let invocation = try Invocation(
                command: "scroll",
                arguments: ["--direction", "down", "--amount", "0"],
                allowedOptions: scroll?.optionNames
            )
            _ = try invocation.integer("amount", default: 3, minimum: 1)
            return "a zero scroll amount was accepted"
        } catch CLIError.usage {
            // Expected: a scroll event always has a positive line count.
        } catch {
            return "a zero scroll amount did not produce a usage error"
        }
        for (error, expected) in [(CLIError.focusUnavailable, "focus_unavailable"),
                                  (CLIError.permissionDenied("Permission missing"), "accessibility_permission_denied"),
                                  (CLIError.accessibility("Draft mismatch"), "accessibility_error")] {
            let context = ExecutionContext()
            guard report(error, showUsage: false, to: context) == 77,
                  let data = context.stdout.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? JSON,
                  payload["code"] as? String == expected,
                  payload["error"] is String else { return "accessibility error classification failed" }
        }
        guard CommandRegistry.command(named: "focused")?.optionNames.contains("pid") == true else {
            return "focused command lost app-scoped observation"
        }
        if let failure = checkKeyGuard() { return failure }
        if let failure = checkStatelessCLI() { return failure }
        if let failure = checkSchemaDescribesEveryCommand() { return failure }
        return nil
    }

    private static func checkKeyGuard() -> String? {
        let command = CommandRegistry.command(named: "key")
        guard command?.risk == .externalCommit,
              command?.optionNames.isSuperset(of: ["pid", "target-path", "require-value"]) == true else {
            return "guarded key options or risk classification missing"
        }
        do {
            let basic = try Invocation(command: "key", arguments: ["--key", "tab"])
            guard try KeyGuard.parse(basic) == nil else { return "ordinary key unexpectedly requires a draft" }
            let full = try Invocation(command: "key", arguments: ["--pid", "123", "--target-path", "0.1", "--require-value", "draft"])
            guard let draft = try KeyGuard.parse(full) else { return "complete key guard was ignored" }
            for mask in 0..<16 {
                var posted = false
                do {
                    try draft.perform(writable: { mask & 1 != 0 }, focused: { mask & 2 != 0 },
                                      matches: { mask & 4 != 0 }, frontmost: { mask & 8 != 0 },
                                      post: { posted = true })
                    if mask != 15 { return "unsafe guarded key was allowed" }
                } catch CLIError.accessibility {
                    if mask == 15 { return "valid guarded key was blocked" }
                }
                if posted != (mask == 15) { return "guarded key posted despite failed preconditions" }
            }
            for args in [
                ["--target-path", "0.1"], ["--require-value", "draft"],
                ["--target-path", "0.1", "--require-value", "draft"],
                ["--pid", "123", "--target-path", "0.1"],
                ["--pid", "123", "--require-value", "draft"],
                ["--pid", "123", "--target-path", "0.1", "--require-value", "\n"],
                ["--pid", "0", "--target-path", "0.1", "--require-value", "draft"]
            ] {
                do {
                    _ = try KeyGuard.parse(Invocation(command: "key", arguments: args))
                    return "incomplete guarded key accepted"
                } catch CLIError.usage { }
            }
        } catch { return "guarded key self-test failed: \(error)" }
        return nil
    }

    private static func checkStatelessCLI() -> String? {
        for name in ["serve", "workflow", "snapshot", "changes"] {
            guard CommandRegistry.command(named: name) == nil,
                  CommandRegistry.execute([name]).status == 64 else {
                return "removed stateful command was accepted: \(name)"
            }
        }
        for arguments in [
            ["--no-service", "schema"], ["schema", "--no-log"],
            ["schema", "--lease", "old-token"], ["schema", "unexpected"]
        ] {
            guard CommandRegistry.execute(arguments).status == 64 else {
                return "removed option or unexpected positional was silently accepted"
            }
        }
        let profiled = CommandRegistry.execute(["schema", "--profile"])
        let first = CommandRegistry.execute(["schema"])
        let second = CommandRegistry.execute(["schema"])
        guard profiled.status == 0, profiled.stderr.hasPrefix("profile elapsed_ms="),
              !profiled.stderr.contains("cache_"), first.status == 0, second.status == 0,
              first.stdout == second.stdout, first.stdout == profiled.stdout,
              first.stderr.isEmpty, second.stderr.isEmpty else {
            return "invocations leaked output or profiling state"
        }
        return nil
    }

    /// The schema is how an agent discovers what exists, so it has to stay complete.
    private static func checkSchemaDescribesEveryCommand() -> String? {
        let response = CommandRegistry.execute(["schema"])
        guard let object = try? JSONSerialization.jsonObject(with: Data(response.stdout.utf8)) as? JSON,
              let commands = object["commands"] as? [JSON] else {
            return "the schema command did not produce readable JSON"
        }
        guard object["schemaVersion"] as? Int == 2,
              commands.count == CommandRegistry.all.count,
              commands.contains(where: { $0["name"] as? String == "schema" }) else {
            return "the schema omitted a command"
        }
        return nil
    }
}
