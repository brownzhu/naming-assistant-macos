import Foundation

/// A user-controlled category label, portable filename token and local hints.
/// Hidden options remain stored so showing fewer categories does not lose edits.
public struct NamingCategoryOption: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var token: String
    public var keywords: [String]
    public var isVisible: Bool

    public init(id: String, label: String, token: String, keywords: [String], isVisible: Bool = true) {
        self.id = id
        self.label = label
        self.token = token
        self.keywords = keywords
        self.isVisible = isVisible
    }
}

/// Pure local category configuration. Decoding does not imply validity; callers
/// must validate before saving or using edited preferences for naming.
public struct NamingCategoryPreferences: Codable, Equatable, Sendable {
    public var options: [NamingCategoryOption]
    public var defaultID: String

    public init(options: [NamingCategoryOption], defaultID: String) {
        self.options = options
        self.defaultID = defaultID
    }

    public static var standard: Self {
        Self(options: [
            NamingCategoryOption(id: "life", label: "生活", token: "life", keywords: [
                "life", "travel", "trip", "recipe", "recipes", "holiday", "vacation", "cooking", "grocery",
                "生活", "旅行", "旅游", "食谱", "假期", "烹饪", "购物",
            ]),
            NamingCategoryOption(id: "research", label: "科研", token: "research", keywords: [
                "research", "paper", "experiment", "experiments", "cem", "eit", "uniqueness", "reconstruction", "regularization",
                "科研", "论文", "实验", "唯一性", "重建", "正则化", "电阻抗", "电极模型",
            ]),
            NamingCategoryOption(id: "engineering", label: "工程", token: "engineering", keywords: [
                "engineering", "swift", "python", "code", "build", "debug", "compiler", "software", "repository",
                "工程", "代码", "编程", "构建", "调试", "软件", "编译",
            ]),
            NamingCategoryOption(id: "learning", label: "学习", token: "learning", keywords: [
                "learning", "study", "lecture", "lectures", "course", "courses", "tutorial", "homework", "exercise", "textbook",
                "学习", "课程", "讲义", "教材", "作业", "习题", "教程",
            ]),
            NamingCategoryOption(id: "admin", label: "管理", token: "admin", keywords: [
                "admin", "invoice", "invoices", "reimbursement", "application", "permit", "receipt", "receipts", "visa",
                "管理", "发票", "报销", "申请", "许可", "签证", "收据",
            ]),
        ], defaultID: "research")
    }

    /// Returns an unchanged valid value; never silently fixes identifiers,
    /// labels, tokens or the user's chosen default.
    public func validated() throws -> Self {
        guard (1...20).contains(options.count) else { throw NamingCategoryPreferencesError.invalidOptionCount }
        var ids = Set<String>()
        var tokens = Set<String>()
        for option in options {
            guard Self.hasVisibleText(option.id), option.id.utf8.count <= 128,
                  !Self.containsUnsafeScalar(option.id) else { throw NamingCategoryPreferencesError.invalidID }
            guard ids.insert(option.id).inserted else { throw NamingCategoryPreferencesError.duplicateID }
            guard NamingCategoryToken.isValid(option.token) else { throw NamingCategoryPreferencesError.invalidToken }
            guard tokens.insert(option.token).inserted else { throw NamingCategoryPreferencesError.duplicateToken }
            guard Self.hasVisibleText(option.label), option.label.count <= 32,
                  !Self.containsUnsafeScalar(option.label) else { throw NamingCategoryPreferencesError.invalidLabel }
            guard option.keywords.count <= 30 else { throw NamingCategoryPreferencesError.invalidKeywordCount }
            for keyword in option.keywords {
                guard Self.hasVisibleText(keyword), keyword.utf8.count <= 64,
                      !Self.containsUnsafeScalar(keyword) else { throw NamingCategoryPreferencesError.invalidKeyword }
            }
        }
        guard options.contains(where: \.isVisible) else { throw NamingCategoryPreferencesError.noVisibleOptions }
        guard options.contains(where: { $0.id == defaultID && $0.isVisible }) else {
            throw NamingCategoryPreferencesError.invalidDefault
        }
        return self
    }

    public var visibleOptions: [NamingCategoryOption] { options.filter(\.isVisible) }

    /// A hint from user-configured, distinct literal keywords. Hidden options
    /// are excluded. Unknown or equally supported choices remain a user choice.
    /// No user-supplied regex, model, file access or naming mutation is used.
    public func recommendation(for text: String) -> NamingCategoryOption? {
        guard (try? validated()) != nil, !text.isEmpty, text.utf8.count <= 255,
              !Self.containsUnsafeScalar(text) else { return nil }
        let source = Self.separatedWords(text)
        var best: NamingCategoryOption?
        var bestScore = 0
        var tied = false
        for option in visibleOptions {
            let distinctKeywords = Set(option.keywords.map {
                Self.separatedWords($0.trimmingCharacters(in: .whitespacesAndNewlines))
            })
            let score = distinctKeywords.filter { keyword in
                if keyword.unicodeScalars.contains(where: Self.isCJK) {
                    return source.contains(keyword)
                }
                guard keyword.unicodeScalars.allSatisfy(\.isASCII),
                      keyword.unicodeScalars.contains(where: {
                          (97...122).contains($0.value) || (48...57).contains($0.value)
                      }) else { return false }
                return Self.containsBoundedLiteral(keyword, in: source)
            }.count
            guard score > 0 else { continue }
            if score > bestScore {
                best = option
                bestScore = score
                tied = false
            } else if score == bestScore {
                tied = true
            }
        }
        return tied ? nil : best
    }

    private static func hasVisibleText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func containsUnsafeScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            switch $0.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: return true
            default: return false
            }
        }
    }

    private static func separatedWords(_ value: String) -> String {
        value.replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
            .lowercased()
    }

    private static func containsBoundedLiteral(_ keyword: String, in source: String) -> Bool {
        var start = source.startIndex
        while start < source.endIndex,
              let range = source.range(of: keyword, options: .literal, range: start..<source.endIndex) {
            let preceding = source[..<range.lowerBound].unicodeScalars.last
            let following = source[range.upperBound...].unicodeScalars.first
            if !(preceding.map(isWordScalar) ?? false) && !(following.map(isWordScalar) ?? false) {
                return true
            }
            start = range.upperBound
        }
        return false
    }

    private static func isWordScalar(_ value: Unicode.Scalar) -> Bool {
        switch value.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default: return false
        }
    }

    private static func isCJK(_ value: Unicode.Scalar) -> Bool {
        (0x3400...0x4DBF).contains(value.value) || (0x4E00...0x9FFF).contains(value.value)
            || (0xF900...0xFAFF).contains(value.value) || (0x20000...0x2FA1F).contains(value.value)
            || (0x3040...0x30FF).contains(value.value) || (0x31F0...0x31FF).contains(value.value)
            || (0x1100...0x11FF).contains(value.value) || (0x3130...0x318F).contains(value.value)
            || (0xAC00...0xD7AF).contains(value.value)
    }
}

// Shared by custom preferences and NamingProfile's additional category API.
enum NamingCategoryToken {
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 24 else { return false }
        let bytes = Array(value.utf8)
        guard (97...122).contains(bytes[0]), bytes.last != 95 else { return false }
        var wasUnderscore = false
        for byte in bytes {
            if byte == 95 {
                guard !wasUnderscore else { return false }
                wasUnderscore = true
            } else {
                guard (97...122).contains(byte) || (48...57).contains(byte) else { return false }
                wasUnderscore = false
            }
        }
        return true
    }
}

public enum NamingCategoryPreferencesError: Error, Equatable, Sendable, LocalizedError {
    case invalidOptionCount, invalidID, duplicateID, invalidToken, duplicateToken
    case invalidLabel, invalidKeywordCount, invalidKeyword, noVisibleOptions, invalidDefault

    public var errorDescription: String? {
        switch self {
        case .invalidOptionCount: return "分类数量需要在 1 到 20 项之间。"
        case .invalidID: return "分类标识不可为空、过长或包含不可见控制字符。"
        case .duplicateID: return "分类标识不可重复。"
        case .invalidToken: return "英文分类词须以小写字母开头，使用小写字母、数字和单个下划线，最多 24 字节。"
        case .duplicateToken: return "英文分类词不可重复，包括暂时隐藏的分类。"
        case .invalidLabel: return "显示名称须为 1 到 32 个字，不含不可见控制字符。"
        case .invalidKeywordCount: return "每项分类最多设置 30 个关键词。"
        case .invalidKeyword: return "关键词不可为空，每词最多 64 字节，且不可含不可见控制字符。"
        case .noVisibleOptions: return "至少显示一项分类。"
        case .invalidDefault: return "默认分类须存在并处于显示状态。"
        }
    }
}
