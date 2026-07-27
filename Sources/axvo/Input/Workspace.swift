import AppKit
import Foundation

func runningApplications() -> [JSON] {
    NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular }
        .map {
            [
                "name": $0.localizedName ?? "",
                "pid": Int($0.processIdentifier),
                "bundleId": $0.bundleIdentifier ?? ""
            ] as JSON
        }
}

func activateApplication(pidText: String) throws {
    guard let pid = pid_t(pidText), let app = NSRunningApplication(processIdentifier: pid) else {
        throw CLIError.usage("--pid must identify a running application")
    }
    app.unhide()
    guard app.activate(options: [.activateIgnoringOtherApps]) else {
        throw CLIError.accessibility("Could not activate process \(pid)")
    }
}

private let openableSchemes = ["http", "https", "slack"]

func openURL(_ text: String) throws {
    guard let url = URL(string: text), let scheme = url.scheme,
          openableSchemes.contains(scheme.lowercased()) else {
        throw CLIError.usage("open requires an http, https, or slack URL")
    }
    guard NSWorkspace.shared.open(url) else {
        throw CLIError.accessibility("Could not open \(text)")
    }
}

func requestAccessibilityPermission() -> JSON {
    // This is the documented string value of kAXTrustedCheckOptionPrompt. Using the
    // literal avoids Swift 6's shared-mutable-global diagnostic on the C declaration.
    let trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    return [
        "trusted": trusted,
        "message": trusted
            ? "Accessibility access is enabled."
            : "A permission prompt was requested. Enable your terminal in System Settings, then rerun the command."
    ]
}
