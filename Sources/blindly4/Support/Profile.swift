import Foundation

final class Profile {
    private let started = ContinuousClock.now
    var attributeReads = 0
    var batchReads = 0
    var visitedNodes = 0
    var pasteWaitMilliseconds = 0

    func render() -> String {
        let elapsed = started.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        return String(
            format: "profile elapsed_ms=%.1f ax_reads=%d batch_reads=%d visited_nodes=%d paste_wait_ms=%d\n",
            milliseconds, attributeReads, batchReads, visitedNodes, pasteWaitMilliseconds
        )
    }
}
