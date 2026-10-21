import Foundation

/// Performs literal and regex-based search and replace on strings.
public enum SearchReplace {

    /// Result of a search/replace operation.
    public struct Result {
        /// The string after replacement, or nil if no match was found.
        public let output: String?
        /// Whether a match was found.
        public let matched: Bool
    }

    /// Performs search and replace on `source` using the given parameters.
    ///
    /// - Parameters:
    ///   - source: The input string to search within.
    ///   - searchTerm: The pattern to search for.
    ///   - replaceTerm: The replacement string (may contain backreferences for regex mode).
    ///   - flags: Controls regex mode, case sensitivity, and match-all behavior.
    /// - Returns: A `Result` with the output string and whether a match was found.
    public static func replace(
        in source: String,
        searchTerm: String,
        replaceTerm: String,
        flags: RenameFlags
    ) -> Result {
        guard !source.isEmpty, !searchTerm.isEmpty else {
            return Result(output: nil, matched: false)
        }

        // Normalize to NFC so NFD filenames from older HFS+ volumes match
        // NFC search terms typed by the user. Also fold common non-breaking
        // whitespace (U+00A0) to regular space, matching PowerRename behavior
        // so a copy-pasted NBSP in either side doesn't silently miss matches.
        let source = source
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let searchTerm = searchTerm
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        let replaceTerm = replaceTerm.precomposedStringWithCanonicalMapping

        if flags.contains(.useRegex) {
            return regexReplace(
                in: source,
                pattern: searchTerm,
                replacement: replaceTerm,
                caseSensitive: flags.contains(.caseSensitive),
                matchAll: flags.contains(.matchAll)
            )
        } else {
            return literalReplace(
                in: source,
                searchTerm: searchTerm,
                replaceTerm: replaceTerm,
                caseSensitive: flags.contains(.caseSensitive),
                matchAll: flags.contains(.matchAll)
            )
        }
    }

    // MARK: - Regex Replace

    private static func regexReplace(
        in source: String,
        pattern: String,
        replacement: String,
        caseSensitive: Bool,
        matchAll: Bool
    ) -> Result {
        var options: NSRegularExpression.Options = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return Result(output: nil, matched: false)
        }

        let range = NSRange(source.startIndex..., in: source)

        // Check if there's a match at all
        guard regex.firstMatch(in: source, range: range) != nil else {
            return Result(output: nil, matched: false)
        }

        let result: String
        if matchAll {
            result = regex.stringByReplacingMatches(
                in: source,
                range: range,
                withTemplate: replacement
            )
        } else {
            // Replace only the first match. We can't use `replaceMatches(in:range:)`
            // here because it iterates every match inside the given range — so a
            // pattern like `(.*)` would also hit the zero-width match after the
            // last character and produce a doubled replacement.
            guard let firstMatch = regex.firstMatch(in: source, range: range) else {
                return Result(output: nil, matched: false)
            }
            let expanded = regex.replacementString(
                for: firstMatch,
                in: source,
                offset: 0,
                template: replacement
            )
            result = (source as NSString).replacingCharacters(in: firstMatch.range, with: expanded)
        }

        return Result(output: result, matched: true)
    }

    // MARK: - Literal Replace

    private static func literalReplace(
        in source: String,
        searchTerm: String,
        replaceTerm: String,
        caseSensitive: Bool,
        matchAll: Bool
    ) -> Result {
        let compareOptions: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var working = source
        var matched = false

        if matchAll {
            // Replace all occurrences
            var searchRange = working.startIndex..<working.endIndex
            while let foundRange = working.range(
                of: searchTerm,
                options: compareOptions,
                range: searchRange
            ) {
                matched = true
                working.replaceSubrange(foundRange, with: replaceTerm)
                // Continue searching after the replacement
                let newStart = working.index(
                    foundRange.lowerBound,
                    offsetBy: replaceTerm.count,
                    limitedBy: working.endIndex
                ) ?? working.endIndex
                searchRange = newStart..<working.endIndex
            }
        } else {
            // Replace first occurrence only
            if let foundRange = working.range(
                of: searchTerm,
                options: compareOptions
            ) {
                matched = true
                working.replaceSubrange(foundRange, with: replaceTerm)
            }
        }

        return Result(output: matched ? working : nil, matched: matched)
    }
}
