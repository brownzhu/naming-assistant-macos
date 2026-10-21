import Foundation

/// Words that should remain lowercase in title case, unless they are the first or last word.
/// Matches the exception list from PowerRename's GetTransformedFileName.
enum TitleCaseRules {
    static let exceptions: Set<String> = [
        "a", "an", "to", "the",
        "at", "by", "for", "in",
        "of", "on", "up",
        "and", "as", "but", "or", "nor",
    ]
}
