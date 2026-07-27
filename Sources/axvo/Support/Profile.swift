import Foundation

final class Profile {
    private let started = ContinuousClock.now
    let enabled: Bool
    var attributeReads = 0
    var batchReads = 0
    var visitedNodes = 0
    var cacheHits = 0
    var cacheMisses = 0
    var pasteWaitMilliseconds = 0

    init(enabled: Bool) { self.enabled = enabled }

    func render() -> String {
        let elapsed = started.duration(to: .now)
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        return String(
            format: "profile elapsed_ms=%.1f ax_reads=%d batch_reads=%d visited_nodes=%d cache_hits=%d cache_misses=%d paste_wait_ms=%d\n",
            milliseconds, attributeReads, batchReads, visitedNodes, cacheHits, cacheMisses, pasteWaitMilliseconds
        )
    }
}
