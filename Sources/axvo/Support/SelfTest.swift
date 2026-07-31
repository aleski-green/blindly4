import Foundation

/// Dependency-free checks for the generic hot path and the CLI contracts that guard
/// unsafe input. Kept in the executable so `blindy --self-test` validates the build
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
        let normalizedA = SearchKey(pid: 1, title: "  ÁlEx ", role: "Button", value: nil)
        let normalizedB = SearchKey(pid: 1, title: "alex", role: "button", value: nil)
        guard normalizedA == normalizedB else { return "search-key normalization is inconsistent" }
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
        if let failure = checkSessionLogging() { return failure }
        if let failure = checkSchemaDescribesEveryCommand() { return failure }
        return nil
    }

    private static func checkSessionLogging() -> String? {
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000.123)
        let filename = SessionLogger.filename(for: startedAt)
        guard filename == "session_s_20250615T150640123Z.ndjson" else {
            return "session log filename is not a UTC start timestamp"
        }

        let response = ExecutionResponse(
            stdout: "{\"characters\":6,\"ok\":true}\n",
            stderr: "",
            status: 0
        )
        let event = SessionLogger.commandEvent(
            arguments: ["type", "--text", "secret"],
            response: response,
            elapsedMilliseconds: 12.5,
            at: startedAt
        )
        guard event["cmd"] as? String == "type",
              event["args"] as? [String] == ["--text", "secret"],
              event["timestamp"] is Int64,
              (event["stdout"] as? JSON)?["characters"] as? Int == 6 else {
            return "session command event omitted plaintext arguments, timestamp, or stdout JSON"
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blindy-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logger = SessionLogger(enabled: true, logDirectory: directory, startedAt: startedAt)
        logger.log(
            arguments: ["type", "--text", "secret"],
            response: response,
            elapsedMilliseconds: 12.5
        )
        logger.finish(reason: "self_test")

        let url = directory.appendingPathComponent(filename)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "session logger did not create its NDJSON file"
        }
        let lines = text.split(separator: "\n")
        guard lines.count == 3,
              let command = try? JSONSerialization.jsonObject(
                with: Data(lines[1].utf8)
              ) as? JSON,
              command["event"] as? String == "command",
              command["args"] as? [String] == ["--text", "secret"] else {
            return "session logger did not write start, command, and end NDJSON events"
        }

        let suppressedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blindy-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: suppressedDirectory) }
        let suppressed = SessionLogger(
            enabled: true,
            logDirectory: suppressedDirectory,
            startedAt: startedAt
        )
        suppressed.log(
            arguments: ["apps", "--no-log"],
            response: response,
            elapsedMilliseconds: 1
        )
        suppressed.finish(reason: "self_test")
        guard !FileManager.default.fileExists(atPath: suppressedDirectory.path) else {
            return "--no-log created an empty session log"
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
        guard commands.count == CommandRegistry.all.count,
              commands.contains(where: { $0["name"] as? String == "schema" }) else {
            return "the schema omitted a command"
        }
        return nil
    }
}
