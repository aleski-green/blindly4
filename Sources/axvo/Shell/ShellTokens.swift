/// Splits an interactive shell line into arguments, honouring quotes and backslashes.
func shellTokens(_ line: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false
    for character in line {
        if escaping {
            current.append(character)
            escaping = false
        } else if character == "\\" {
            escaping = true
        } else if let activeQuote = quote {
            if character == activeQuote { quote = nil }
            else { current.append(character) }
        } else if character == "\"" || character == "'" {
            quote = character
        } else if character.isWhitespace {
            if !current.isEmpty { tokens.append(current); current = "" }
        } else {
            current.append(character)
        }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
}
