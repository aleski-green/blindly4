import Foundation

typealias JSON = [String: Any]

func printJSON(_ value: Any) {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
        fputs("{\"error\":\"could not encode JSON\"}\n", stderr)
        return
    }
    print(text)
}
