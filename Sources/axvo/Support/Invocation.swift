import ApplicationServices
import Foundation

/// One parsed command line: `blindy press --path 0.2 --pid 123`.
struct Invocation {
    let command: String
    let options: [String: String]
    let flags: Set<String>
    let positionals: [String]

    init(command: String, arguments: [String]) throws {
        var options: [String: String] = [:]
        var flags: Set<String> = []
        var positionals: [String] = []
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            guard token.hasPrefix("--") else {
                positionals.append(token)
                index += 1
                continue
            }
            if token == "--require-selected" {
                flags.insert("require-selected")
                index += 1
                continue
            }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw CLIError.usage("Missing value for \(token)")
            }
            options[String(token.dropFirst(2))] = arguments[index + 1]
            index += 2
        }
        self.command = command
        self.options = options
        self.flags = flags
        self.positionals = positionals
    }

    func optional(_ name: String) -> String? {
        options[name]
    }

    func hasFlag(_ name: String) -> Bool { flags.contains(name) }

    func value(_ name: String) throws -> String {
        guard let value = options[name] else {
            throw CLIError.usage("\(command) requires --\(name)")
        }
        return value
    }

    func integer(_ name: String, default fallback: Int, minimum: Int) throws -> Int {
        guard let text = options[name] else { return fallback }
        guard let number = Int(text) else { throw CLIError.usage("--\(name) must be an integer") }
        guard number >= minimum else { throw CLIError.usage("--\(name) must be >= \(minimum)") }
        return number
    }

    func number(_ name: String) throws -> Double {
        guard let value = Double(try value(name)) else {
            throw CLIError.usage("--\(name) must be numeric")
        }
        return value
    }

    /// The application element addressed by `--pid`, defaulting to the frontmost app.
    func application() throws -> AXUIElement {
        try targetApplication(pidText: options["pid"])
    }

    /// The element addressed by `--path` within the target application.
    func element(profile: Profile? = nil) throws -> (path: String, element: AXUIElement) {
        let path = try value("path")
        return (path, try elementAtPath(path, from: try application(), profile: profile))
    }
}
