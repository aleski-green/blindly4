import AppKit
import Foundation

/// Best-effort audit logging for one local-service or direct session.
/// The file is opened lazily so `--no-log` commands do not create empty log files.
final class SessionLogger {
    enum Mode {
        case treePaths
        case full

        static var fromEnvironment: Mode {
            ProcessInfo.processInfo.environment["BLINDLY4_LOG_MODE"] == "full" ? .full : .treePaths
        }

        var name: String {
            switch self {
            case .treePaths: return "tree_paths"
            case .full: return "full"
            }
        }
    }

    private static let discoveryCommands: Set<String> = [
        "show", "tree", "find", "inspect", "actions", "focused"
    ]

    private let enabled: Bool
    private let mode: Mode
    private let startedAt: Date
    private let sessionID: String
    private let logDirectory: URL
    private var file: FileHandle?
    private var finished = false
    private var nextSnapshotNumber = 1
    private var latestSnapshotIDByPID: [Int: String] = [:]

    init(
        enabled: Bool = ProcessInfo.processInfo.environment["BLINDLY4_NO_LOG"] != "1",
        mode: Mode = .fromEnvironment,
        logDirectory: URL? = nil,
        startedAt: Date = Date()
    ) {
        self.enabled = enabled
        self.mode = mode
        self.startedAt = startedAt
        self.sessionID = UUID().uuidString
        self.logDirectory = logDirectory ?? Self.defaultLogDirectory()
    }

    func log(
        arguments: [String],
        response: ExecutionResponse,
        elapsedMilliseconds: Double,
        workflow: JSON? = nil
    ) {
        guard enabled, !arguments.contains("--no-log"), !finished else { return }
        guard ensureOpen() else { return }

        let commandArguments = arguments.filter { $0 != "--no-log" }
        let metadata = Self.targetMetadata(arguments: commandArguments)
        let event: JSON
        switch mode {
        case .full:
            var fullEvent = Self.commandEvent(
                arguments: commandArguments,
                response: response,
                elapsedMilliseconds: elapsedMilliseconds,
                at: Date()
            )
            fullEvent["session"] = sessionID
            fullEvent.merge(metadata) { _, new in new }
            if let workflow { fullEvent.merge(workflow) { _, new in new } }
            event = fullEvent
        case .treePaths:
            var compactEvent = treePathsEvent(
                commandArguments: commandArguments,
                response: response,
                elapsedMilliseconds: elapsedMilliseconds,
                metadata: metadata,
                at: Date()
            )
            if let workflow { compactEvent.merge(workflow) { _, new in new } }
            event = compactEvent
        }
        write(event)
    }

    func finish(reason: String) {
        guard enabled, !finished else { return }
        finished = true
        guard file != nil else { return }

        var event = Self.baseEvent(at: Date())
        event["event"] = "session.end"
        event["session"] = sessionID
        event["reason"] = reason
        write(event)
        try? file?.close()
        file = nil
    }

    deinit {
        if !finished {
            finish(reason: "process_exit")
        }
    }

    static func commandEvent(
        arguments: [String],
        response: ExecutionResponse,
        elapsedMilliseconds: Double,
        at date: Date
    ) -> JSON {
        var event = baseEvent(at: date)
        event["event"] = "command"
        event["cmd"] = arguments.first ?? ""
        event["args"] = Array(arguments.dropFirst())
        event["status"] = Int(response.status)
        event["ms"] = elapsedMilliseconds
        event["stdout"] = decodedOutput(response.stdout)
        event["stderr"] = decodedOutput(response.stderr)
        return event
    }

    static func filename(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return "session_s_\(formatter.string(from: date)).ndjson"
    }

    private func ensureOpen() -> Bool {
        if file != nil { return true }
        do {
            try FileManager.default.createDirectory(
                at: logDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let url = logDirectory.appendingPathComponent(Self.filename(for: startedAt))
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            file = try FileHandle(forWritingTo: url)
            try file?.seekToEnd()

            var event = Self.baseEvent(at: startedAt)
            event["event"] = "session.start"
            event["session"] = sessionID
            event["servicePid"] = Int(ProcessInfo.processInfo.processIdentifier)
            if mode == .treePaths {
                event["mode"] = mode.name
            }
            write(event)
            return true
        } catch {
            file = nil
            return false
        }
    }

    private func write(_ event: JSON) {
        guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
            return
        }
        file?.write(data)
        file?.write(Data([0x0A]))
    }

    private static func baseEvent(at date: Date) -> JSON {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return [
            "ts": formatter.string(from: date),
            "timestamp": Int64(date.timeIntervalSince1970 * 1_000)
        ]
    }

    private static func decodedOutput(_ text: String) -> Any {
        guard !text.isEmpty else { return NSNull() }
        let data = Data(text.utf8)
        return (try? JSONSerialization.jsonObject(with: data)) ?? text
    }

    private func treePathsEvent(
        commandArguments: [String],
        response: ExecutionResponse,
        elapsedMilliseconds: Double,
        metadata: JSON,
        at date: Date
    ) -> JSON {
        let command = commandArguments.first ?? ""
        var event = Self.baseEvent(at: date)
        event["cmd"] = command
        event["status"] = Int(response.status)
        event["ms"] = elapsedMilliseconds
        event["session"] = sessionID
        event.merge(metadata) { _, new in new }

        if Self.discoveryCommands.contains(command) {
            let snapshotID = "s-\(nextSnapshotNumber)"
            nextSnapshotNumber += 1
            if let pid = metadata["pid"] as? Int {
                latestSnapshotIDByPID[pid] = snapshotID
            }
            event["event"] = "snapshot"
            event["snapshotId"] = snapshotID
            event["snapshot"] = Self.decodedOutput(response.stdout)
        } else {
            event["event"] = "command"
            let pid = metadata["pid"] as? Int
            event["snapshotId"] = pid.flatMap { latestSnapshotIDByPID[$0] } ?? NSNull()
        }
        return event
    }

    private static func targetMetadata(arguments: [String]) -> JSON {
        let pidText = option("pid", in: arguments)
        let requestedPID = pidText.flatMap { pid_t($0) }
        let application = requestedPID.flatMap(NSRunningApplication.init(processIdentifier:))
            ?? (pidText == nil ? NSWorkspace.shared.frontmostApplication : nil)

        var metadata: JSON = [:]
        if let requestedPID {
            metadata["pid"] = Int(requestedPID)
        }
        if let application {
            metadata["app"] = application.localizedName ?? ""
            metadata["pid"] = Int(application.processIdentifier)
            metadata["bundleId"] = application.bundleIdentifier ?? ""
        }
        if let path = option("path", in: arguments) ?? option("target-path", in: arguments) {
            metadata["path"] = path
        }
        return metadata
    }

    private static func option(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--\(name)"),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func defaultLogDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["BLINDLY4_LOG_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        let manager = FileManager.default
        let cwd = URL(fileURLWithPath: manager.currentDirectoryPath, isDirectory: true)
        if let root = packageRoot(startingAt: cwd) {
            return root.appendingPathComponent(".logs", isDirectory: true)
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        if let root = packageRoot(startingAt: executable.deletingLastPathComponent()) {
            return root.appendingPathComponent(".logs", isDirectory: true)
        }
        return cwd.appendingPathComponent(".logs", isDirectory: true)
    }

    private static func packageRoot(startingAt start: URL) -> URL? {
        var directory = start.standardizedFileURL
        while true {
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("Package.swift").path
            ) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
    }
}
