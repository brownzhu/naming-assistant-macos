import Foundation

/// Coordinates expansion of all token types in a replace string.
/// Handles the ordering: enumeration/random tokens first, then the result
/// is used as the replacement template for regex/literal substitution.
public enum TokenExpander {

    /// Pre-processes the replace string by expanding enumeration and randomizer tokens.
    /// This must happen before the regex substitution step.
    ///
    /// - Parameters:
    ///   - replaceTerm: The raw replace string from the user.
    ///   - flags: Controls which token types are active.
    ///   - enumIndex: The current item's enumeration index.
    /// - Returns: The replace string with enum/random tokens expanded.
    public static func expandInlineTokens(
        _ replaceTerm: String,
        flags: RenameFlags,
        enumIndex: Int
    ) -> String {
        var result = replaceTerm

        let enumTokens = flags.contains(.enumerate) ? EnumerationToken.parse(result) : []
        let randTokens = flags.contains(.randomize) ? RandomizerToken.parse(result) : []

        if !enumTokens.isEmpty && !randTokens.isEmpty {
            // Both present: merge and process by offset, right to left.
            // Randomizer wins if at same offset (matches PowerRename behavior).
            var allSpans: [(offset: Int, length: Int, isRandom: Bool, index: Int)] = []

            for (i, t) in enumTokens.enumerated() {
                allSpans.append((t.span.lowerBound, t.span.count, false, i))
            }
            for (i, t) in randTokens.enumerated() {
                allSpans.append((t.span.lowerBound, t.span.count, true, i))
            }

            // Sort by offset descending (right to left)
            allSpans.sort { $0.offset > $1.offset }

            // Remove duplicate offsets — keep randomizer
            var seen = Set<Int>()
            allSpans = allSpans.filter { span in
                if seen.contains(span.offset) { return false }
                seen.insert(span.offset)
                return true
            }

            for span in allSpans {
                let startIdx = result.index(result.startIndex, offsetBy: span.offset)
                let endIdx = result.index(startIdx, offsetBy: span.length)
                let replacement: String

                if span.isRandom {
                    replacement = randTokens[span.index].generate()
                } else {
                    replacement = enumTokens[span.index].formatted(at: enumIndex)
                }

                result.replaceSubrange(startIdx..<endIdx, with: replacement)
            }
        } else if !enumTokens.isEmpty {
            result = EnumerationToken.expand(result, tokens: enumTokens, index: enumIndex)
        } else if !randTokens.isEmpty {
            result = RandomizerToken.expand(result, tokens: randTokens)
        }

        return result
    }

    /// Expands date/time tokens in the replace string using a file's timestamp.
    public static func expandDateTimeTokens(_ text: String, date: Date) -> String {
        DateTimeToken.expand(text, date: date)
    }

    /// Expands metadata tokens in the replace string using extracted patterns.
    public static func expandMetadataTokens(_ text: String, patterns: [String: String]) -> String {
        MetadataToken.expand(text, patterns: patterns)
    }
}
