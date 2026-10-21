import Foundation

/// Parses and expands randomizer tokens: `${rstringalnum=N}`, `${rstringalpha=N}`,
/// `${rstringdigit=N}`, `${ruuidv4}`.
/// Matches PowerRename's Randomizer.h/cpp behavior.
public struct RandomizerToken: Sendable {
    public enum Kind: Sendable {
        case alphanumeric(length: Int)
        case alpha(length: Int)
        case digit(length: Int)
        case uuid
    }

    public let kind: Kind
    /// The range within the original replace string where this token appeared.
    let span: Range<Int>

    public init(kind: Kind, span: Range<Int>) {
        self.kind = kind
        self.span = span
    }

    /// Generates a random string based on the token kind.
    public func generate() -> String {
        switch kind {
        case .alphanumeric(let length):
            return randomString(from: Self.alphanumericChars, length: length)
        case .alpha(let length):
            return randomString(from: Self.alphaChars, length: length)
        case .digit(let length):
            return randomString(from: Self.digitChars, length: length)
        case .uuid:
            return UUID().uuidString.lowercased()
        }
    }

    private static let alphanumericChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let alphaChars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    private static let digitChars = Array("0123456789")

    private func randomString(from chars: [Character], length: Int) -> String {
        guard !chars.isEmpty, length > 0 else { return "" }
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    // MARK: - Parsing

    private static let tokenPattern = try! NSRegularExpression(pattern: #"\$\{.*?\}"#)
    private static let alnumPattern = try! NSRegularExpression(pattern: #"rstringalnum=(\d+)"#)
    private static let alphaPattern = try! NSRegularExpression(pattern: #"rstringalpha=(\d+)"#)
    private static let digitPattern = try! NSRegularExpression(pattern: #"rstringdigit=(\d+)"#)
    private static let uuidPattern = try! NSRegularExpression(pattern: #"ruuidv4"#)

    /// Parses all randomizer tokens from a replace string.
    public static func parse(_ replaceString: String) -> [RandomizerToken] {
        let nsString = replaceString as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = tokenPattern.matches(in: replaceString, range: fullRange)

        var tokens: [RandomizerToken] = []

        for match in matches {
            let matchStr = nsString.substring(with: match.range)
            let span = match.range.location..<(match.range.location + match.range.length)

            if let length = extractInt(from: matchStr, using: alnumPattern) {
                let clamped = max(1, min(length, 260))
                tokens.append(RandomizerToken(kind: .alphanumeric(length: clamped), span: span))
            } else if let length = extractInt(from: matchStr, using: alphaPattern) {
                let clamped = max(1, min(length, 260))
                tokens.append(RandomizerToken(kind: .alpha(length: clamped), span: span))
            } else if let length = extractInt(from: matchStr, using: digitPattern) {
                let clamped = max(1, min(length, 260))
                tokens.append(RandomizerToken(kind: .digit(length: clamped), span: span))
            } else if hasMatch(in: matchStr, using: uuidPattern) {
                tokens.append(RandomizerToken(kind: .uuid, span: span))
            }
        }

        return tokens
    }

    /// Expands all randomizer tokens in a replace string.
    /// Tokens are replaced from right to left to preserve offsets.
    public static func expand(_ replaceString: String, tokens: [RandomizerToken]) -> String {
        var result = replaceString

        for token in tokens.reversed() {
            let generated = token.generate()
            let startIdx = result.index(result.startIndex, offsetBy: token.span.lowerBound)
            let endIdx = result.index(result.startIndex, offsetBy: token.span.upperBound)
            result.replaceSubrange(startIdx..<endIdx, with: generated)
        }

        return result
    }

    private static func extractInt(from text: String, using pattern: NSRegularExpression) -> Int? {
        let range = NSRange(location: 0, length: (text as NSString).length)
        guard let match = pattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let valueStr = (text as NSString).substring(with: match.range(at: 1))
        return Int(valueStr)
    }

    private static func hasMatch(in text: String, using pattern: NSRegularExpression) -> Bool {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return pattern.firstMatch(in: text, range: range) != nil
    }
}
