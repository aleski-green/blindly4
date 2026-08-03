import ApplicationServices
import Foundation

struct SearchKey: Hashable {
    let pid: Int
    let title: String?
    let role: String?
    let value: String?
    let description: String?

    init(pid: Int, title: String?, role: String?, value: String?, description: String? = nil) {
        self.pid = pid
        self.title = Self.normalize(title)
        self.role = Self.normalize(role)
        self.value = Self.normalize(value)
        self.description = Self.normalize(description)
    }

    private static func normalize(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct TargetSignature {
    let role: String
    let title: String
    let value: String
    let description: String
    let identifier: String

    var isStable: Bool {
        !identifier.isEmpty || (!role.isEmpty && (!title.isEmpty || !value.isEmpty || !description.isEmpty))
    }
}

private struct CachedTarget {
    let path: String
    let signature: TargetSignature
    let windowFingerprint: String
    var lastUsed: Date
}

/// Request-local state shared by the socket service. It never reaches disk.
final class AccessibilitySession {
    private var targets: [SearchKey: CachedTarget] = [:]
    private var snapshots: [String: Set<String>] = [:]

    fileprivate func target(for key: SearchKey) -> (path: String, signature: TargetSignature, windowFingerprint: String)? {
        guard var target = targets[key] else { return nil }
        target.lastUsed = Date()
        targets[key] = target
        return (target.path, target.signature, target.windowFingerprint)
    }

    fileprivate func store(path: String, signature: TargetSignature, windowFingerprint: String, for key: SearchKey) {
        guard signature.isStable else { return }
        targets[key] = CachedTarget(path: path, signature: signature, windowFingerprint: windowFingerprint, lastUsed: Date())
    }

    fileprivate func remove(_ key: SearchKey) { targets.removeValue(forKey: key) }

    func storeSnapshot(_ signatures: Set<String>, name: String, pid: Int, path: String) {
        snapshots["\(pid)\u{1F}\(path)\u{1F}\(name)"] = signatures
    }

    func snapshot(name: String, pid: Int, path: String) -> Set<String>? {
        snapshots["\(pid)\u{1F}\(path)\u{1F}\(name)"]
    }
}

/// A memory-only identity for observing generic AX-region changes. Paths are not
/// included because insertions commonly shift them; a new title/value/description is.
func observableSignature(of element: AXUIElement, profile: Profile? = nil) -> String {
    let values = copyAttributes(element, ["AXRole", "AXTitle", "AXValue", "AXDescription", "AXIdentifier"], profile: profile)
    return ["AXRole", "AXTitle", "AXValue", "AXDescription", "AXIdentifier"]
        .map { values[$0].map { String(describing: textValue($0)) } ?? "" }
        .joined(separator: "\u{1F}")
}
private func processID(of element: AXUIElement) -> Int {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    return Int(pid)
}

private func targetSignature(of element: AXUIElement, profile: Profile) -> TargetSignature {
    let values = copyAttributes(element, ["AXRole", "AXTitle", "AXValue", "AXDescription", "AXIdentifier"], profile: profile)
    func text(_ name: String) -> String { values[name].map { String(describing: textValue($0)) } ?? "" }
    return TargetSignature(role: text("AXRole"), title: text("AXTitle"), value: text("AXValue"), description: text("AXDescription"), identifier: text("AXIdentifier"))
}

private func windowFingerprint(of application: AXUIElement, profile: Profile) -> String {
    guard let window = copyElementAttribute(application, "AXFocusedWindow", profile: profile) else { return "" }
    let values = copyAttributes(window, ["AXIdentifier", "AXTitle"], profile: profile)
    return ["AXIdentifier", "AXTitle"].compactMap { values[$0].map { String(describing: textValue($0)) } }.joined(separator: "\u{1F}")
}

private func matches(_ element: AXUIElement, signature: TargetSignature, profile: Profile) -> Bool {
    let current = targetSignature(of: element, profile: profile)
    guard current.role == signature.role else { return false }
    if !signature.identifier.isEmpty { return current.identifier == signature.identifier }
    return current.title == signature.title && current.value == signature.value && current.description == signature.description
}

/// Uses a validated path hint only for one-result lookups. Every hit re-resolves and
/// checks the target before returning it, so stale UI never causes a blind action.
func findCachedOrDescendants(
    root: AXUIElement,
    invocation: Invocation,
    title: String?,
    role: String?,
    value: String?,
    description: String?,
    depth: Int,
    limit: Int,
    context: ExecutionContext
) -> [Match] {
    let key = SearchKey(pid: processID(of: root), title: title, role: role, value: value, description: description)
    let currentFingerprint = windowFingerprint(of: root, profile: context.profile)
    if limit == 1, let cached = context.session.target(for: key) {
        if cached.windowFingerprint == currentFingerprint,
           let element = try? elementAtPath(cached.path, from: root, profile: context.profile),
           matches(element, signature: cached.signature, profile: context.profile) {
            context.profile.cacheHits += 1
            return [Match(path: cached.path, element: element)]
        }
        context.session.remove(key)
    }

    context.profile.cacheMisses += 1
    let found = findDescendants(of: root, depth: depth, limit: limit, profile: context.profile) {
        matches($0, title: title, role: role, value: value, description: description, profile: context.profile)
    }
    if limit == 1, let first = found.first {
        context.session.store(
            path: first.path,
            signature: targetSignature(of: first.element, profile: context.profile),
            windowFingerprint: currentFingerprint,
            for: key
        )
    }
    return found
}
