import ApplicationServices
import Foundation

func copyAttribute(_ element: AXUIElement, _ name: String, profile: Profile? = nil) -> Any? {
    profile?.attributeReads += 1
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

/// Reads only the attributes the caller needs. Batching reduces cross-process AX IPC
/// on complex interfaces; a failed batch falls back to the established single-read path.
func copyAttributes(_ element: AXUIElement, _ names: [String], profile: Profile? = nil) -> [String: Any] {
    guard names.count > 1 else {
        guard let name = names.first, let value = copyAttribute(element, name, profile: profile) else { return [:] }
        return [name: value]
    }
    profile?.batchReads += 1
    profile?.attributeReads += 1
    var values: CFArray?
    let result = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values)
    guard result == .success, let array = values as? [Any], array.count == names.count else {
        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            copyAttribute(element, name, profile: profile).map { (name, $0) }
        })
    }
    return Dictionary(uniqueKeysWithValues: zip(names, array).compactMap { name, value in
        // AX returns AXValue-wrapped AXError values for unavailable members. AXValue
        // also carries positions and sizes, so distinguish the error subtype first.
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else { return (name, value) }
        let axValue = unsafeDowncast(cfValue, to: AXValue.self)
        var axError = AXError.success
        return AXValueGetValue(axValue, .axError, &axError) ? nil : (name, value)
    })
}

func copyElementAttribute(_ element: AXUIElement, _ name: String, profile: Profile? = nil) -> AXUIElement? {
    profile?.attributeReads += 1
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
}

func attributes(of element: AXUIElement, profile: Profile? = nil) -> [String] {
    profile?.attributeReads += 1
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success,
          let array = names as? [String] else { return [] }
    return array
}

func actions(of element: AXUIElement, profile: Profile? = nil) -> [String] {
    profile?.attributeReads += 1
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

func textAttribute(_ element: AXUIElement, _ name: String, profile: Profile? = nil) -> String {
    guard let value = copyAttribute(element, name, profile: profile) else { return "" }
    return String(describing: textValue(value))
}

/// AX text frequently includes invisible directionality markers.  They do not alter
/// what the person sees, so ignore only those markers while otherwise requiring an
/// exact draft match.  In particular, this deliberately rejects prefixes, suffixes,
/// and old text left in a composer.
func sameVisibleText(_ actual: String, _ expected: String) -> Bool {
    let invisibleDirectionality = CharacterSet(charactersIn: "\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
    func normalized(_ text: String) -> String {
        text
            .precomposedStringWithCanonicalMapping
            .unicodeScalars
            .filter { !invisibleDirectionality.contains($0) }
            .map(String.init)
            .joined()
    }
    return normalized(actual) == normalized(expected)
}

/// A draft can be exposed by AXValue, AXTitle, or AXDescription depending on the
/// framework.  Look only inside the writer's own AX subtree, never across the window
/// or message history, so an old message cannot satisfy the send precondition.
func hasExactVisibleText(in root: AXUIElement, expected: String, profile: Profile? = nil) -> Bool {
    !findDescendants(of: root, depth: 4, limit: 1, profile: profile) { element in
        let attributes = copyAttributes(element, ["AXValue", "AXTitle", "AXDescription"], profile: profile)
        return attributes.values.contains { sameVisibleText(String(describing: textValue($0)), expected) }
    }.isEmpty
}

/// The screen point used for a direct click on an AX element. This is derived from
/// the current live element rather than caller-supplied coordinates.
func center(of element: AXUIElement, profile: Profile? = nil) -> CGPoint? {
    let values = copyAttributes(element, ["AXPosition", "AXSize"], profile: profile)
    guard let position = values["AXPosition"], let size = values["AXSize"] else { return nil }
    let positionReference = position as CFTypeRef
    let sizeReference = size as CFTypeRef
    guard CFGetTypeID(positionReference) == AXValueGetTypeID(),
          CFGetTypeID(sizeReference) == AXValueGetTypeID() else { return nil }
    let positionValue = unsafeDowncast(positionReference, to: AXValue.self)
    let sizeValue = unsafeDowncast(sizeReference, to: AXValue.self)
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(positionValue, .cgPoint, &point),
          AXValueGetValue(sizeValue, .cgSize, &dimensions),
          dimensions.width > 0, dimensions.height > 0 else { return nil }
    return CGPoint(x: point.x + dimensions.width / 2, y: point.y + dimensions.height / 2)
}

private let summaryAttributes = [
    "AXRole", "AXSubrole", "AXTitle", "AXDescription", "AXValue",
    "AXIdentifier", "AXEnabled", "AXFocused", "AXSelected", "AXPosition", "AXSize"
]

func summary(of element: AXUIElement, includeAttributes: Bool = false, profile: Profile? = nil) -> JSON {
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    var result: JSON = ["pid": Int(pid)]
    for (name, value) in copyAttributes(element, summaryAttributes, profile: profile) {
            result[String(name.dropFirst(2)).lowercased()] = textValue(value)
    }
    if includeAttributes { result["attributes"] = attributes(of: element, profile: profile).sorted() }
    return result
}

/// A summary plus the fields commands report when a single element is the subject.
func detail(of element: AXUIElement, path: String? = nil, profile: Profile? = nil) -> JSON {
    var result = summary(of: element, includeAttributes: true, profile: profile)
    result["actions"] = actions(of: element, profile: profile).sorted()
    if let path { result["path"] = path }
    return result
}

func children(of element: AXUIElement, includeApplicationWindows: Bool = false, profile: Profile? = nil) -> [AXUIElement] {
    let standardChildren = (copyAttribute(element, "AXChildren", profile: profile) as? [AXUIElement]) ?? []
    guard includeApplicationWindows else { return standardChildren }
    // Electron and some native apps expose their content windows through AXWindows
    // rather than AXChildren on the application element. Treat those windows as
    // navigable children unless a window is already present in AXChildren.
    let alreadyContainsWindow = standardChildren.contains { textAttribute($0, "AXRole", profile: profile) == "AXWindow" }
    guard !alreadyContainsWindow,
          let windows = copyAttribute(element, "AXWindows", profile: profile) as? [AXUIElement] else {
        return standardChildren
    }
    return standardChildren + windows
}

func tree(of element: AXUIElement, depth: Int, remaining: inout Int, includeApplicationWindows: Bool = true, profile: Profile? = nil) -> JSON {
    remaining -= 1
    profile?.visitedNodes += 1
    var node = summary(of: element, profile: profile)
    guard depth > 0, remaining > 0 else { return node }
    var listedChildren: [JSON] = []
    for child in children(of: element, includeApplicationWindows: includeApplicationWindows, profile: profile) {
        guard remaining > 0 else { break }
        listedChildren.append(tree(of: child, depth: depth - 1, remaining: &remaining, includeApplicationWindows: false, profile: profile))
    }
    if !listedChildren.isEmpty { node["children"] = listedChildren }
    return node
}

struct Match {
    let path: String
    let element: AXUIElement
}

/// Depth-first list of every element below `root`, labelled with its AXChildren path.
func descendants(of root: AXUIElement, depth: Int, profile: Profile? = nil) -> [Match] {
    var matches: [Match] = []
    func visit(_ element: AXUIElement, path: String, depth: Int, includeApplicationWindows: Bool) {
        profile?.visitedNodes += 1
        matches.append(Match(path: path, element: element))
        guard depth > 0 else { return }
        for (index, child) in children(of: element, includeApplicationWindows: includeApplicationWindows, profile: profile).enumerated() {
            visit(child, path: path.isEmpty ? String(index) : "\(path).\(index)", depth: depth - 1, includeApplicationWindows: false)
        }
    }
    visit(root, path: "", depth: depth, includeApplicationWindows: true)
    return matches
}

/// Depth-first search that returns as soon as it has enough matches.
func findDescendants(
    of root: AXUIElement,
    depth: Int,
    limit: Int,
    profile: Profile? = nil,
    where predicate: (AXUIElement) -> Bool
) -> [Match] {
    depthFirstMatches(
        root: root,
        depth: depth,
        limit: limit,
        children: { element, isRoot in
            children(of: element, includeApplicationWindows: isRoot, profile: profile)
        },
        matches: predicate,
        onVisit: { profile?.visitedNodes += 1 }
    ).map { Match(path: $0.path, element: $0.node) }
}

func outlineLine(path: String, element: AXUIElement, profile: Profile? = nil) -> String {
    let values = copyAttributes(element, ["AXRole", "AXTitle", "AXValue", "AXDescription"], profile: profile)
    let role = values["AXRole"].map { String(describing: textValue($0)) } ?? ""
    let labels = ["AXTitle", "AXValue", "AXDescription"].map { values[$0].map { String(describing: textValue($0)) } ?? "" }
    let label = labels.first { !$0.isEmpty } ?? ""
    return "\(path.isEmpty ? "root" : path)  \(role)\(label.isEmpty ? "" : "  \(label)")"
}

func matches(_ element: AXUIElement, title: String?, role: String?, value: String?, description: String? = nil, profile: Profile? = nil) -> Bool {
    let requested = [("AXTitle", title), ("AXValue", value), ("AXDescription", description)]
        .compactMap { attribute, query in query.map { (attribute, $0) } }
        + (role.map { [("AXRole", $0)] } ?? [])
    let values = copyAttributes(element, requested.map(\.0), profile: profile)
    func contains(_ attribute: String, _ query: String?) -> Bool {
        guard let query, !query.isEmpty else { return true }
        return (values[attribute].map { String(describing: textValue($0)) } ?? "").localizedCaseInsensitiveContains(query)
    }
    let expectedRole = role.map { $0.hasPrefix("AX") ? $0 : "AX\($0)" }
    return contains("AXTitle", title)
        && contains("AXValue", value)
        && contains("AXDescription", description)
        && (expectedRole == nil || (values["AXRole"].map { String(describing: textValue($0)) } ?? "") == expectedRole)
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
