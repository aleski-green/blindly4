import Foundation

/// Optional draft guard for keyboard input. Missing guard fields must never
/// silently downgrade a guarded command to ordinary system-wide input.
struct KeyGuard {
    let path: String
    let expected: String

    static func parse(_ invocation: Invocation) throws -> KeyGuard? {
        let path = invocation.optional("target-path")
        let expected = invocation.optional("require-value")
        if path == nil && expected == nil { return nil }
        guard let path, !path.isEmpty, let expected, !isVisiblyEmpty(expected),
              let pid = invocation.optional("pid"), let number = Int32(pid), number > 0 else {
            throw CLIError.usage("Guarded key requires --pid, --target-path and nonempty --require-value")
        }
        return KeyGuard(path: path, expected: expected)
    }

    /// Kept independent of AX so failure paths can be checked without UI input.
    func perform(writable: () -> Bool, focused: () -> Bool, matches: () -> Bool,
                 frontmost: () -> Bool, post: () throws -> Void) throws {
        guard writable(), matches(), focused(), frontmost() else {
            throw CLIError.accessibility("Key blocked: the intended app and focused text control must contain exactly --require-value")
        }
        try post()
    }
}
