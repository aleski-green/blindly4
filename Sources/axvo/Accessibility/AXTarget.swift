import AppKit
import ApplicationServices

func targetApplication(pidText: String?) throws -> AXUIElement {
    if let pidText {
        guard let pid = pid_t(pidText) else { throw CLIError.usage("--pid must be an integer") }
        return AXUIElementCreateApplication(pid)
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
        throw CLIError.accessibility("No frontmost application found")
    }
    return AXUIElementCreateApplication(app.processIdentifier)
}

/// Resolves a dotted AXChildren path such as `0.2.1` below `root`.
func elementAtPath(_ path: String, from root: AXUIElement, profile: Profile? = nil) throws -> AXUIElement {
    guard !path.isEmpty else { return root }
    var element = root
    for (pathIndex, part) in path.split(separator: ".").enumerated() {
        guard let index = Int(part), index >= 0 else { throw CLIError.usage("Invalid path: \(path)") }
        let available = children(of: element, includeApplicationWindows: pathIndex == 0, profile: profile)
        guard index < available.count else {
            throw CLIError.accessibility("Path \(path) does not exist (index \(index) is out of range)")
        }
        element = available[index]
    }
    return element
}
