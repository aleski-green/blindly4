struct PathMatch<Node> {
    let path: String
    let node: Node
}

/// Generic, bounded DFS used by AX lookup and unit-tested without macOS UI state.
func depthFirstMatches<Node>(
    root: Node,
    depth: Int,
    limit: Int,
    children: (Node, Bool) -> [Node],
    matches: (Node) -> Bool,
    onVisit: () -> Void = {}
) -> [PathMatch<Node>] {
    var found: [PathMatch<Node>] = []
    func visit(_ node: Node, path: String, remainingDepth: Int, isRoot: Bool) -> Bool {
        onVisit()
        if matches(node) {
            found.append(PathMatch(path: path, node: node))
            if found.count == limit { return true }
        }
        guard remainingDepth > 0 else { return false }
        for (index, child) in children(node, isRoot).enumerated() {
            if visit(child, path: path.isEmpty ? String(index) : "\(path).\(index)", remainingDepth: remainingDepth - 1, isRoot: false) {
                return true
            }
        }
        return false
    }
    _ = visit(root, path: "", remainingDepth: depth, isRoot: true)
    return found
}
