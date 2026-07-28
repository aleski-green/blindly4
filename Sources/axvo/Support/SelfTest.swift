import Foundation

/// Dependency-free checks for the generic hot path. Kept in the executable because
/// the macOS Command Line Tools runtime used by this package does not ship XCTest.
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
        return nil
    }
}
