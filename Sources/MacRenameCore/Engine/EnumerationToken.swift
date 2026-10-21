import Foundation

/// Parses and expands `${start=X,increment=Y,padding=Z}` enumeration tokens.
/// Matches PowerRename's Enumerating.h/cpp behavior.
public struct EnumerationToken: Sendable {
    public let start: Int
    public let increment: Int
    public let padding: Int
    /// The range within the original replace string where this token appeared.
    let span: Range<Int>

    public init(start: Int = 0, increment: Int = 1, padding: Int = 0, span: Range<Int>) {
        self.start = start
        self.increment = increment
        self.padding = padding
        self.span = span
    }

    /// Computes the enumerated value for the given item index.
    public func value(at index: Int) -> Int {
        start + (index * increment)
    }

    /// Formats the enumerated value with zero-padding.
    public func formatted(at index: Int) -> String {
        let val = value(at: index)
        if padding > 0 {
            let str = String(val)
            // If the number (including sign) is already longer than padding, return as-is
            if str.count >= padding {
                return str
            }
            if val < 0 {
                // Pad after the minus sign
                let digits = String(str.dropFirst())
                return "-" + String(repeating: "0", count: max(0, padding - 1 - digits.count)) + digits
            }
            return String(repeating: "0", count: max(0, padding - str.count)) + str
        }
        return String(val)
    }

    // MARK: - Parsing

    /// Pattern to find enumeration tokens: ${...}
    private static let tokenPattern = try! NSRegularExpression(pattern: #"\$\{.*?\}"#)
    private static let startPattern = try! NSRegularExpression(pattern: #"start=(-?\d+)"#)
    private static let incrementPattern = try! NSRegularExpression(pattern: #"increment=(-?\d+)"#)
    private static let paddingPattern = try! NSRegularExpression(pattern: #"padding=(\d+)"#)

    /// Parses all enumeration tokens from a replace string.
    /// Returns tokens sorted by their position in the string.
    public static func parse(_ replaceString: String) -> [EnumerationToken] {
        let nsString = replaceString as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = tokenPattern.matches(in: replaceString, range: fullRange)

        var tokens: [EnumerationToken] = []

        for match in matches {
            let matchStr = nsString.substring(with: match.range)

            // Skip if this is a randomizer token
            if matchStr.contains("rstring") || matchStr.contains("ruuidv4") {
                continue
            }

            let start = extractInt(from: matchStr, using: startPattern) ?? 0
            let increment = extractInt(from: matchStr, using: incrementPattern) ?? 1
            let padding = extractInt(from: matchStr, using: paddingPattern).map { max(0, min($0, 255)) } ?? 0

            let span = match.range.location..<(match.range.location + match.range.length)
            tokens.append(EnumerationToken(start: start, increment: increment, padding: padding, span: span))
        }

        return tokens
    }

    /// Expands all enumeration tokens in a replace string for the given index.
    /// Tokens are replaced from right to left to preserve offsets.
    public static func expand(_ replaceString: String, tokens: [EnumerationToken], index: Int) -> String {
        var result = replaceString

        // Process from right to left to preserve string indices
        for token in tokens.reversed() {
            let formatted = token.formatted(at: index)
            let startIdx = result.index(result.startIndex, offsetBy: token.span.lowerBound)
            let endIdx = result.index(result.startIndex, offsetBy: token.span.upperBound)
            result.replaceSubrange(startIdx..<endIdx, with: formatted)
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
}
