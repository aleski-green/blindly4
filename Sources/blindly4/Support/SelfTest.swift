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
        let lease = CommandRegistry.command(named: "lease")
        guard press?.risk == .externalCommit, press?.optionNames.contains("require-selected") == true else {
            return "command metadata lost the risk classification or its declared options"
        }
        guard lease?.risk == .localState,
              lease?.requiresAccessibility == false,
              lease?.optionNames.isSuperset(of: ["owner", "token", "ttl"]) == true else {
            return "workflow lease command metadata is incorrect"
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
        if let failure = checkWorkflowLeases() { return failure }
        if let failure = checkSessionLogging() { return failure }
        if let failure = checkSchemaDescribesEveryCommand() { return failure }
        return nil
    }

    private static func checkWorkflowLeases() -> String? {
        let leases = WorkflowLeaseCoordinator()
        let startedAt = Date(timeIntervalSince1970: 1_750_000_000)
        guard case .success(let lease) = leases.acquire(owner: "agent-a", ttlSeconds: 30, now: startedAt) else {
            return "workflow lease could not be acquired"
        }
        guard case .busy(let retryAfterMilliseconds) = leases.authorize(token: nil, now: startedAt),
              retryAfterMilliseconds == 30_000 else {
            return "a held workflow lease did not block a read without its token"
        }
        guard case .granted(let authorized?) = leases.authorize(token: lease.token, now: startedAt),
              authorized.id == lease.id,
              authorized.owner == "agent-a" else {
            return "the workflow lease token did not authorize its owner"
        }
        guard case .busy = leases.release(token: "wl_wrong", now: startedAt) else {
            return "an invalid workflow lease token released another workflow"
        }
        guard case .granted(let released?) = leases.release(token: lease.token, now: startedAt),
              released.id == lease.id,
              case .granted(nil) = leases.authorize(token: nil, now: startedAt) else {
            return "a workflow lease did not release cleanly"
        }
        let expiringLeases = WorkflowLeaseCoordinator()
        guard case .success(let expiringLease) = expiringLeases.acquire(owner: "agent-b", ttlSeconds: 1, now: startedAt),
              case .invalidToken = expiringLeases.authorize(token: expiringLease.token, now: startedAt.addingTimeInterval(2)) else {
            return "an expired workflow lease token was accepted"
        }
        do {
            let parsed = try WorkflowLeaseArguments(["find", "--title", "Messages", "--lease", "wl_secret"])
            guard parsed.commandArguments == ["find", "--title", "Messages"],
                  parsed.token == "wl_secret",
                  parsed.loggingArguments == ["find", "--title", "Messages", "--lease", "<redacted>"] else {
                return "workflow lease arguments did not separate or redact the token"
            }
        } catch {
            return "workflow lease arguments failed to parse"
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blindly4-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logger = SessionLogger(enabled: true, mode: .full, logDirectory: directory, startedAt: startedAt)
        let serviceLeases = WorkflowLeaseCoordinator()
        let acquired = CommandRegistry.execute(
            ["lease", "acquire", "--owner", "self-test", "--ttl", "30"],
            logger: logger,
            workflowLeases: serviceLeases
        )
        guard acquired.status == 0,
              let acquireData = acquired.stdout.data(using: .utf8),
              let acquireJSON = try? JSONSerialization.jsonObject(with: acquireData) as? JSON,
              let token = acquireJSON["token"] as? String else {
            return "lease acquire did not return a workflow token"
        }
        let authorizedRead = CommandRegistry.execute(
            ["apps", "--lease", token],
            logger: logger,
            workflowLeases: serviceLeases
        )
        let blockedRead = CommandRegistry.execute(["apps"], logger: logger, workflowLeases: serviceLeases)
        logger.finish(reason: "self_test")
        guard authorizedRead.status == 0, blockedRead.status == 75 else {
            return "workflow leases did not apply consistently to read-only commands"
        }
        let logURL = directory.appendingPathComponent(SessionLogger.filename(for: startedAt))
        guard let logText = try? String(contentsOf: logURL, encoding: .utf8),
              !logText.contains(token),
              logText.contains("workflowId"),
              logText.contains("workflowOwner") else {
            return "workflow logs leaked a token or omitted workflow metadata"
        }
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
            .appendingPathComponent("blindly4-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pidOne = Int(ProcessInfo.processInfo.processIdentifier)
        let pidTwo = pidOne + 1
        let compactLogger = SessionLogger(
            enabled: true,
            mode: .treePaths,
            logDirectory: directory,
            startedAt: startedAt
        )
        compactLogger.log(
            arguments: ["show", "--pid", "\(pidOne)"],
            response: ExecutionResponse(stdout: "visible tree secret", stderr: "", status: 0),
            elapsedMilliseconds: 1
        )
        compactLogger.log(
            arguments: ["paste", "--pid", "\(pidOne)", "--target-path", "0.3", "--text", "secret"],
            response: response,
            elapsedMilliseconds: 2
        )
        compactLogger.log(
            arguments: ["find", "--pid", "\(pidTwo)", "--title", "private label"],
            response: ExecutionResponse(stdout: "{\"matches\":[]}", stderr: "", status: 0),
            elapsedMilliseconds: 3
        )
        compactLogger.log(
            arguments: ["press", "--pid", "\(pidOne)", "--path", "0.4"],
            response: response,
            elapsedMilliseconds: 4
        )
        compactLogger.finish(reason: "self_test")

        let url = directory.appendingPathComponent(filename)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "session logger did not create its NDJSON file"
        }
        let lines = text.split(separator: "\n")
        guard lines.count == 6,
              let start = decodedEvent(from: lines[0]),
              let firstSnapshot = decodedEvent(from: lines[1]),
              let paste = decodedEvent(from: lines[2]),
              let secondSnapshot = decodedEvent(from: lines[3]),
              let press = decodedEvent(from: lines[4]),
              start["mode"] as? String == "tree_paths",
              firstSnapshot["event"] as? String == "snapshot",
              firstSnapshot["snapshotId"] as? String == "s-1",
              firstSnapshot["snapshot"] as? String == "visible tree secret",
              secondSnapshot["snapshotId"] as? String == "s-2",
              paste["event"] as? String == "command",
              paste["path"] as? String == "0.3",
              paste["snapshotId"] as? String == "s-1",
              press["snapshotId"] as? String == "s-1",
              paste["args"] == nil,
              paste["stdout"] == nil,
              paste["stderr"] == nil,
              !text.contains("\"--text\"") else {
            return "tree-path logging did not keep snapshots and commands compact"
        }

        let fullDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blindly4-self-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fullDirectory) }
        let fullLogger = SessionLogger(
            enabled: true,
            mode: .full,
            logDirectory: fullDirectory,
            startedAt: startedAt
        )
        fullLogger.log(
            arguments: ["type", "--text", "secret"],
            response: response,
            elapsedMilliseconds: 12.5
        )
        fullLogger.finish(reason: "self_test")
        let fullURL = fullDirectory.appendingPathComponent(filename)
        guard let fullText = try? String(contentsOf: fullURL, encoding: .utf8),
              let fullCommand = fullText.split(separator: "\n").dropFirst().first.flatMap(decodedEvent),
              fullCommand["event"] as? String == "command",
              fullCommand["args"] as? [String] == ["--text", "secret"],
              (fullCommand["stdout"] as? JSON)?["characters"] as? Int == 6 else {
            return "full logging did not preserve the legacy command event"
        }

        let suppressedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blindly4-self-test-\(UUID().uuidString)", isDirectory: true)
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

    private static func decodedEvent(from line: Substring) -> JSON? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? JSON
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
