import ApplicationServices
import Foundation

func copyAttribute(_ element: AXUIElement, _ name: String) -> Any? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func copyElementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

func attributes(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success,
          let array = names as? [String] else { return [] }
    return array
}

func actions(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let array = names as? [String] else { return [] }
    return array
}

func textValue(_ value: Any) -> Any {
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number }
    if let url = value as? URL { return url.absoluteString }
    let cfValue = value as CFTypeRef
    if CFGetTypeID(cfValue) == AXValueGetTypeID() {
        let axValue = unsafeDowncast(cfValue, to: AXValue.self)
        var point = CGPoint.zero
        if AXValueGetValue(axValue, .cgPoint, &point) { return ["x": point.x, "y": point.y] }
        var size = CGSize.zero
        if AXValueGetValue(axValue, .cgSize, &size) { return ["width": size.width, "height": size.height] }
        var rect = CGRect.zero
        if AXValueGetValue(axValue, .cgRect, &rect) {
            return ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
        }
    }
    return String(describing: value)
}

func textAttribute(_ element: AXUIElement, _ name: String) -> String {
    guard let value = copyAttribute(element, name) else { return "" }
    return String(describing: textValue(value))
}

private let summaryAttributes = [
    "AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue",
    "AXIdentifier", "AXEnabled", "AXFocused", "AXPosition", "AXSize"
]

func summary(of element: AXUIElement, includeAttributes: Bool = false) -> JSON {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    var result: JSON = ["pid": Int(pid)]
    for name in summaryAttributes {
        if let value = copyAttribute(element, name) {
            result[String(name.dropFirst(2)).lowercased()] = textValue(value)
        }
    }
    if includeAttributes { result["attributes"] = attributes(of: element).sorted() }
    return result
}

/// A summary plus the fields commands report when a single element is the subject.
func detail(of element: AXUIElement, path: String? = nil) -> JSON {
    var result = summary(of: element, includeAttributes: true)
    result["actions"] = actions(of: element).sorted()
    if let path { result["path"] = path }
    return result
}

func children(of element: AXUIElement) -> [AXUIElement] {
    let standardChildren = (copyAttribute(element, "AXChildren") as? [AXUIElement]) ?? []
    // Electron and some native apps expose their content windows through AXWindows
    // rather than AXChildren on the application element. Treat those windows as
    // navigable children unless a window is already present in AXChildren.
    let alreadyContainsWindow = standardChildren.contains { textAttribute($0, "AXRole") == "AXWindow" }
    guard textAttribute(element, "AXRole") == "AXApplication", !alreadyContainsWindow,
          let windows = copyAttribute(element, "AXWindows") as? [AXUIElement] else {
        return standardChildren
    }
    return standardChildren + windows
}

func tree(of element: AXUIElement, depth: Int, remaining: inout Int) -> JSON {
    remaining -= 1
    var node = summary(of: element)
    guard depth > 0, remaining > 0 else { return node }
    var listedChildren: [JSON] = []
    for child in children(of: element) {
        guard remaining > 0 else { break }
        listedChildren.append(tree(of: child, depth: depth - 1, remaining: &remaining))
    }
    if !listedChildren.isEmpty { node["children"] = listedChildren }
    return node
}

struct Match {
    let path: String
    let element: AXUIElement
}

/// Depth-first list of every element below `root`, labelled with its AXChildren path.
func descendants(of root: AXUIElement, depth: Int) -> [Match] {
    var matches: [Match] = []
    func visit(_ element: AXUIElement, path: String, depth: Int) {
        matches.append(Match(path: path, element: element))
        guard depth > 0 else { return }
        for (index, child) in children(of: element).enumerated() {
            visit(child, path: path.isEmpty ? String(index) : "\(path).\(index)", depth: depth - 1)
        }
    }
    visit(root, path: "", depth: depth)
    return matches
}

func outlineLine(path: String, element: AXUIElement) -> String {
    let role = textAttribute(element, "AXRole")
    let labels = ["AXTitle", "AXValue", "AXDescription"].map { textAttribute(element, $0) }
    let label = labels.first { !$0.isEmpty } ?? ""
    return "\(path.isEmpty ? "root" : path)  \(role)\(label.isEmpty ? "" : "  \(label)")"
}

func matches(_ element: AXUIElement, title: String?, role: String?, value: String?) -> Bool {
    func contains(_ attribute: String, _ query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return textAttribute(element, attribute).localizedCaseInsensitiveContains(query)
    }
    let expectedRole = role.map { $0.hasPrefix("AX") ? $0 : "AX\($0)" }
    return contains("AXTitle", title)
        && contains("AXValue", value)
        && (expectedRole == nil || textAttribute(element, "AXRole") == expectedRole)
}

/// Writes an AX attribute, translating the AXError into a readable failure.
func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef, hint: String = "") throws {
    let error = AXUIElementSetAttributeValue(element, name as CFString, value)
    guard error == .success else {
        throw CLIError.accessibility("Setting \(name) failed: \(error.rawValue)\(hint.isEmpty ? "" : ". \(hint)")")
    }
}

func performAction(_ element: AXUIElement, _ name: String) throws {
    let error = AXUIElementPerformAction(element, name as CFString)
    guard error == .success else {
        throw CLIError.accessibility("\(name) failed: \(error.rawValue)")
    }
}

func requireAccessibility() throws {
    guard AXIsProcessTrusted() else {
        throw CLIError.accessibility("Accessibility access is not enabled. Run `blindy request-permission`, then enable your terminal in System Settings > Privacy & Security > Accessibility.")
    }
}
