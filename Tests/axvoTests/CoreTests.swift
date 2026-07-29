import Foundation
import XCTest
@testable import axvo

final class CoreTests: XCTestCase {
    func testDepthFirstSearchStopsAtLimit() {
        struct Node {
            let name: String
            let children: [Node]
        }
        let root = Node(name: "root", children: [
            Node(name: "first", children: [Node(name: "target", children: [])]),
            Node(name: "second", children: [Node(name: "target", children: [])])
        ])
        var visits = 0

        let result = depthFirstMatches(
            root: root,
            depth: 3,
            limit: 1,
            children: { node, _ in node.children },
            matches: { $0.name == "target" },
            onVisit: { visits += 1 }
        )

        XCTAssertEqual(result.map(\.path), ["0.0"])
        XCTAssertEqual(visits, 3)
    }

    func testVisibleTextComparisonIsExactExceptForDirectionality() {
        XCTAssertTrue(sameVisibleText("\u{200E}hello\u{2069}", "hello"))
        XCTAssertFalse(sameVisibleText("old hello", "hello"))
        XCTAssertFalse(sameVisibleText("hello old", "hello"))
        XCTAssertTrue(isVisiblyEmpty("\n\u{200E}"))
        XCTAssertFalse(isVisiblyEmpty("\nold draft"))
    }

    func testSearchKeysNormalizeCaseWhitespaceAndDiacritics() {
        let first = SearchKey(pid: 1, title: "  ÁlEx ", role: "Button", value: nil)
        let second = SearchKey(pid: 1, title: "alex", role: "button", value: nil)
        XCTAssertEqual(first, second)
    }

    func testInvocationRejectsUnknownOptions() {
        XCTAssertThrowsError(
            try Invocation(
                command: "find",
                arguments: ["--titel", "Settings"],
                allowedOptions: ["title"]
            )
        ) { error in
            guard case CLIError.usage(let message) = error else {
                return XCTFail("Expected a usage error")
            }
            XCTAssertTrue(message.contains("--titel"))
        }
    }

    func testCommandMetadataExposesRiskAndOptions() {
        let command = Command(
            "press",
            "--path PATH [--require-selected]",
            summary: "Press a control.",
            risk: .externalCommit
        ) { _, _ in }

        XCTAssertEqual(command.optionNames, ["path", "require-selected"])
        XCTAssertEqual(command.metadata["risk"] as? String, "external-commit")
    }

    func testShowMenuIsClassifiedAsUIMutation() {
        let command = CommandRegistry.command(named: "show-menu")
        XCTAssertEqual(command?.risk, .uiMutation)
        XCTAssertEqual(command?.optionNames, ["path", "pid"])
    }

    func testOptionValuesAreNotMistakenForHelpRequests() {
        XCTAssertFalse(CommandRegistry.requestsCommandHelp(["--text", "help"]))
        XCTAssertFalse(CommandRegistry.requestsCommandHelp(["--value", "-h"]))
        XCTAssertTrue(CommandRegistry.requestsCommandHelp(["help"]))
        XCTAssertTrue(CommandRegistry.requestsCommandHelp(["-h"]))
        XCTAssertTrue(CommandRegistry.requestsCommandHelp(["--path", "0.2", "--help"]))
    }

    func testCommandWithHelpAsAValueDoesNotPrintHelp() {
        // `find` is read-only, so this stays harmless whether or not the host granted
        // Accessibility permission.
        let response = CommandRegistry.execute(["find", "--title", "help"])
        XCTAssertFalse(response.stdout.contains("Risk:"))
    }

    func testSchemaDescribesEveryCommandIncludingItself() throws {
        let response = CommandRegistry.execute(["schema"])
        let object = try JSONSerialization.jsonObject(with: Data(response.stdout.utf8)) as? JSON
        let commands = try XCTUnwrap(object?["commands"] as? [JSON])

        XCTAssertEqual(commands.count, CommandRegistry.all.count)
        XCTAssertTrue(commands.contains { $0["name"] as? String == "schema" })
    }
}
