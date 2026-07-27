import Darwin
import Foundation

/// A minimal readline replacement: history, cursor movement, and tab completion.
final class LineEditor {
    private let commands: [String]
    private let options: [String]
    private var history: [String] = []
    private var historyIndex: Int?
    private var buffer: [Character] = []
    private var cursor = 0

    init(commands: [String], options: [String]) {
        self.commands = commands
        self.options = options
    }

    func readLine(prompt: String) -> String? {
        // Piped input remains useful for scripts and automated tests.
        guard isatty(STDIN_FILENO) != 0 else { return Swift.readLine() }
        guard let restore = enterRawMode() else { return Swift.readLine() }
        defer { restore() }

        buffer = []
        cursor = 0
        historyIndex = nil
        write(prompt)

        while let byte = readByte() {
            switch byte {
            case 3: // Ctrl-C
                write("^C\r\n")
                return ""
            case 4: // Ctrl-D
                if buffer.isEmpty { write("\r\n"); return nil }
            case 10, 13:
                let result = String(buffer)
                write("\r\n")
                if !result.isEmpty, history.last != result { history.append(result) }
                return result
            case 8, 127: // Backspace
                guard cursor > 0 else { continue }
                buffer.remove(at: cursor - 1)
                cursor -= 1
                render(prompt)
            case 9: // Tab
                complete(prompt)
            case 27: // Escape sequences for arrow keys
                guard readByte() == 91, let direction = readByte() else { continue }
                handleArrow(direction, prompt: prompt)
            case 32...126:
                buffer.insert(Character(UnicodeScalar(byte)), at: cursor)
                cursor += 1
                render(prompt)
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Terminal

    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    private func render(_ prompt: String) {
        write("\r\(prompt)\(String(buffer))\u{001B}[K")
        let charactersAfterCursor = buffer.count - cursor
        if charactersAfterCursor > 0 { write("\u{001B}[\(charactersAfterCursor)D") }
    }

    private func readByte() -> UInt8? {
        var byte: UInt8 = 0
        let count = withUnsafeMutableBytes(of: &byte) {
            Darwin.read(STDIN_FILENO, $0.baseAddress, 1)
        }
        return count == 1 ? byte : nil
    }

    /// Switches the terminal to raw mode, returning a closure that restores it.
    private func enterRawMode() -> (() -> Void)? {
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | ISIG)
        withUnsafeMutableBytes(of: &raw.c_cc) { controlCharacters in
            controlCharacters[Int(VMIN)] = 1
            controlCharacters[Int(VTIME)] = 0
        }
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { return nil }
        return { var restored = original; tcsetattr(STDIN_FILENO, TCSAFLUSH, &restored) }
    }

    // MARK: - Editing

    private func handleArrow(_ direction: UInt8, prompt: String) {
        switch direction {
        case 65: // Up
            if historyIndex == nil, !history.isEmpty { historyIndex = history.count - 1 }
            else if let index = historyIndex, index > 0 { historyIndex = index - 1 }
            guard let index = historyIndex else { return }
            replaceBuffer(with: history[index], prompt: prompt)
        case 66: // Down
            if let index = historyIndex, index < history.count - 1 {
                historyIndex = index + 1
                replaceBuffer(with: history[index + 1], prompt: prompt)
            } else {
                historyIndex = nil
                replaceBuffer(with: "", prompt: prompt)
            }
        case 67: // Right
            guard cursor < buffer.count else { return }
            cursor += 1
            render(prompt)
        case 68: // Left
            guard cursor > 0 else { return }
            cursor -= 1
            render(prompt)
        default:
            return
        }
    }

    private func replaceBuffer(with text: String, prompt: String) {
        buffer = Array(text)
        cursor = buffer.count
        render(prompt)
    }

    private func complete(_ prompt: String) {
        var start = cursor
        while start > 0 && !buffer[start - 1].isWhitespace { start -= 1 }
        let partial = String(buffer[start..<cursor])
        let isFirstToken = !buffer[..<start].contains { $0.isWhitespace }
        let choices = (isFirstToken ? commands : options).filter { $0.hasPrefix(partial) }

        if choices.count == 1, let choice = choices.first {
            // Every command option currently expects a value, so a trailing space is
            // useful after completing either a command or an option.
            let replacement = Array(choice + " ")
            buffer.replaceSubrange(start..<cursor, with: replacement)
            cursor = start + replacement.count
            render(prompt)
        } else if !choices.isEmpty {
            write("\r\n\(choices.joined(separator: "  "))\r\n")
            render(prompt)
        }
    }
}
