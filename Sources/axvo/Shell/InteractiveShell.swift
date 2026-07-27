import Foundation

/// Commands the shell answers itself rather than dispatching to the registry.
private let builtins = ["exit", "quit", "help"]

func runInteractiveShell() {
    let editor = LineEditor(
        commands: (CommandRegistry.names + builtins).sorted(),
        options: CommandRegistry.optionFlags
    )
    print("blindy interactive shell — type `help` for commands, `exit` to close.")

    while let line = editor.readLine(prompt: "blindy> ") {
        let tokens = shellTokens(line)
        guard let command = tokens.first else { continue }
        switch command {
        case "exit", "quit":
            return
        case "help":
            print(usage())
        case "shell":
            print("Already in the blindy shell.")
        default:
            // Commands run in this process, so the shell keeps one accessibility
            // grant and reports failures without exiting.
            do { try CommandRegistry.run(tokens) } catch { report(error, showUsage: false) }
        }
    }
}
