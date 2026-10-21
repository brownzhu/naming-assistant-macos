import Foundation

/// Expands metadata pattern tokens ($CAMERA_MAKE, $ISO, etc.) in a replace string.
/// Matches PowerRename's GetMetadataFileName behavior.
public enum MetadataToken {

    /// Checks whether the replace string contains any metadata patterns.
    public static func containsTokens(in text: String) -> Bool {
        // Quick check: must contain $ followed by an uppercase letter
        guard text.contains("$") else { return false }
        for pattern in MetadataPatterns.allPatternNames {
            if text.contains("$\(pattern)") {
                return true
            }
        }
        return false
    }

    /// Expands metadata tokens in the replace string using the provided pattern map.
    ///
    /// - Parameters:
    ///   - text: The replace string containing $PATTERN_NAME tokens.
    ///   - patterns: Map of pattern names to their extracted values.
    /// - Returns: The string with metadata tokens replaced by values.
    public static func expand(_ text: String, patterns: [String: String]) -> String {
        var result = text

        // Process longest patterns first to avoid partial matches
        // (e.g., $DATE_TAKEN_YYYY before $DATE_TAKEN_YY)
        let sortedNames = MetadataPatterns.allPatternNames.sorted { $0.count > $1.count }

        for name in sortedNames {
            let token = "$\(name)"
            guard result.contains(token) else { continue }

            if let value = patterns[name], !value.isEmpty {
                result = result.replacingOccurrences(of: token, with: value)
            }
            // If no value found, leave the token as-is (matches PowerRename behavior)
        }

        return result
    }
}
