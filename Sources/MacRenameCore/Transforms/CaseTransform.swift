import Foundation

/// Applies text case transformations to filenames.
/// Matches PowerRename's GetTransformedFileName behavior.
public enum CaseTransform {

    /// Applies the given transformation to a filename, respecting name/extension scoping.
    public static func apply(
        _ transform: TextTransform,
        to name: String,
        flags: RenameFlags
    ) -> String {
        // Folders have no extension concept
        let isExtensionOnly = flags.contains(.extensionOnly)
        let isNameOnly = flags.contains(.nameOnly)

        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension

        if isNameOnly && !ext.isEmpty {
            // Transform stem only, preserve extension
            let transformed = applyTransform(transform, to: stem)
            return "\(transformed).\(ext)"
        } else if isExtensionOnly && !ext.isEmpty {
            // Transform extension only, preserve stem
            let transformed = applyTransform(transform, to: ext)
            return "\(stem).\(transformed)"
        } else {
            // Transform the full name
            return applyTransform(transform, to: name)
        }
    }

    private static func applyTransform(_ transform: TextTransform, to text: String) -> String {
        switch transform {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titlecase:
            return toTitleCase(text)
        case .capitalized:
            return toCapitalized(text)
        }
    }

    /// Title case: capitalize each word except exception words (unless first or last word).
    private static func toTitleCase(_ text: String) -> String {
        let words = splitIntoWords(text)
        guard !words.isEmpty else { return text }

        var result = text
        let lowered = text.lowercased()

        // Process words in reverse order to maintain string indices
        for (index, word) in words.enumerated().reversed() {
            let isFirst = index == 0
            let isLast = index == words.count - 1
            let loweredWord = lowered[word.range].trimmingCharacters(in: .whitespaces)

            let shouldCapitalize: Bool
            if isFirst || isLast {
                shouldCapitalize = true
            } else if TitleCaseRules.exceptions.contains(loweredWord) {
                shouldCapitalize = false
            } else {
                shouldCapitalize = true
            }

            if shouldCapitalize {
                result = capitalizeFirstLetter(of: word.range, in: result)
            } else {
                result = lowercaseRange(word.range, in: result)
            }
        }

        return result
    }

    /// Capitalized: capitalize the first letter of every word, lowercase the rest.
    private static func toCapitalized(_ text: String) -> String {
        let words = splitIntoWords(text)
        guard !words.isEmpty else { return text }

        var result = text.lowercased()

        for word in words.reversed() {
            // Adjust range for lowercased string (same structure for ASCII-compatible text)
            result = capitalizeFirstLetter(of: word.range, in: result)
        }

        return result
    }

    // MARK: - Word Splitting

    private struct Word {
        let range: Range<String.Index>
        let text: String
    }

    private static func splitIntoWords(_ text: String) -> [Word] {
        var words: [Word] = []
        var wordStart: String.Index?

        for index in text.indices {
            let char = text[index]
            let isWordChar = char.isLetter || char.isNumber || char == "'"

            if isWordChar {
                if wordStart == nil {
                    wordStart = index
                }
            } else {
                if let start = wordStart {
                    let range = start..<index
                    words.append(Word(range: range, text: String(text[range])))
                    wordStart = nil
                }
            }
        }

        // Handle last word
        if let start = wordStart {
            let range = start..<text.endIndex
            words.append(Word(range: range, text: String(text[range])))
        }

        return words
    }

    private static func capitalizeFirstLetter(
        of range: Range<String.Index>,
        in text: String
    ) -> String {
        guard range.lowerBound < text.endIndex else { return text }
        var result = text
        let firstCharRange = range.lowerBound..<text.index(after: range.lowerBound)
        result.replaceSubrange(firstCharRange, with: text[firstCharRange].uppercased())
        return result
    }

    private static func lowercaseRange(
        _ range: Range<String.Index>,
        in text: String
    ) -> String {
        var result = text
        result.replaceSubrange(range, with: text[range].lowercased())
        return result
    }
}
