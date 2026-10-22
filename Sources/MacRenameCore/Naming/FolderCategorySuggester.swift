import Foundation

/// A small keyword hint, not an assertion about the folder's contents.
/// The UI must continue offering all categories and require a user choice.
public struct FolderCategoryRecommendation: Equatable, Sendable {
    public let category: NamingCategory
    public let matchedKeywords: [String]

    public init(category: NamingCategory, matchedKeywords: [String]) {
        self.category = category
        self.matchedKeywords = matchedKeywords
    }
}

/// Pure text-only classification. No file access, model request or naming
/// mutation is performed. Unknown input and tied categories have no suggestion.
public enum FolderCategorySuggester {
    public static func recommend(for text: String) -> FolderCategoryRecommendation? {
        guard !text.isEmpty, text.utf8.count <= 255,
              !text.unicodeScalars.contains(where: {
                  switch $0.properties.generalCategory {
                  case .control, .format, .lineSeparator, .paragraphSeparator:
                      return true
                  default:
                      return false
                  }
              }) else { return nil }

        // Camel-case boundaries are meaningful; substrings inside an English
        // word are not. Chinese phrases are deliberately a finite glossary.
        let separated = text
            .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
            .lowercased()
        let tokens = Set(separated.split(whereSeparator: { character in
            !character.unicodeScalars.allSatisfy {
                (97...122).contains($0.value) || (48...57).contains($0.value)
            }
        }).map(String.init))

        var best: FolderCategoryRecommendation?
        var bestScore = 0
        var tied = false
        for entry in glossary {
            let englishHits = entry.english.filter { tokens.contains($0) }
            let chineseHits = entry.chinese.filter { text.contains($0) }
            // Repeating a keyword cannot outvote a different category.
            let hits = Set(englishHits).union(chineseHits).sorted()
            let score = hits.count
            guard score > 0 else { continue }
            if score > bestScore {
                best = FolderCategoryRecommendation(category: entry.category, matchedKeywords: hits)
                bestScore = score
                tied = false
            } else if score == bestScore {
                tied = true
            }
        }
        return tied ? nil : best
    }

    private struct Keywords: Sendable {
        let category: NamingCategory
        let english: Set<String>
        let chinese: Set<String>
    }

    // Broad words such as "test", "notes", "project" and "report" are
    // intentionally absent: they do not distinguish these five categories.
    private static let glossary: [Keywords] = [
        Keywords(category: .research,
                 english: ["research", "paper", "experiment", "experiments", "cem", "eit", "uniqueness", "reconstruction", "regularization"],
                 chinese: ["科研", "论文", "实验", "唯一性", "重建", "正则化", "电阻抗", "电极模型"]),
        Keywords(category: .engineering,
                 english: ["engineering", "swift", "python", "code", "build", "debug", "compiler", "software", "repository"],
                 chinese: ["工程", "代码", "编程", "构建", "调试", "软件", "编译"]),
        Keywords(category: .learning,
                 english: ["learning", "study", "lecture", "lectures", "course", "courses", "tutorial", "homework", "exercise", "textbook"],
                 chinese: ["学习", "课程", "讲义", "教材", "作业", "习题", "教程"]),
        Keywords(category: .admin,
                 english: ["admin", "invoice", "invoices", "reimbursement", "application", "permit", "receipt", "receipts", "visa"],
                 chinese: ["管理", "发票", "报销", "申请", "许可", "签证", "收据"]),
        Keywords(category: .life,
                 english: ["life", "travel", "trip", "recipe", "recipes", "holiday", "vacation", "cooking", "grocery"],
                 chinese: ["生活", "旅行", "旅游", "食谱", "假期", "烹饪", "购物"]),
    ]
}
