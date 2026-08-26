import Foundation

typealias JSON = [String: Any]

struct ExecutionResponse: Codable {
    let stdout: String
    let stderr: String
    let status: Int32
}

final class ExecutionContext {
    let session: AccessibilitySession
    let profile: Profile
    let workflowLock: WorkflowLock?
    let workflowToken: String?
    private(set) var stdout = ""
    private(set) var stderr = ""

    init(
        session: AccessibilitySession = AccessibilitySession(),
        profileEnabled: Bool = false,
        workflowLock: WorkflowLock? = nil,
        workflowToken: String? = nil
    ) {
        self.session = session
        self.profile = Profile(enabled: profileEnabled)
        self.workflowLock = workflowLock
        self.workflowToken = workflowToken
    }

    func writeStdout(_ text: String) { stdout += text }
    func writeStderr(_ text: String) { stderr += text }

    func response(status: Int32) -> ExecutionResponse {
        ExecutionResponse(stdout: stdout, stderr: stderr, status: status)
    }
}

func printJSON(_ value: Any, to context: ExecutionContext) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        context.writeStderr("{\"error\":\"could not encode JSON\"}\n")
        return
    }
    context.writeStdout(text + "\n")
}

func emit(_ response: ExecutionResponse) {
    FileHandle.standardOutput.write(Data(response.stdout.utf8))
    FileHandle.standardError.write(Data(response.stderr.utf8))
}
