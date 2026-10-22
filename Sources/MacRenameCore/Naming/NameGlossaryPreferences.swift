import Foundation

public struct NameGlossaryEntry: Codable, Equatable, Sendable {
    public var source: String
    public var target: String
    public init(source: String, target: String) { self.source = source; self.target = target }
}

/// Complete local dictionary snapshot: deleting a row disables that built-in
/// phrase too. Unknown remaining text is never silently discarded.
public struct NameGlossaryPreferences: Codable, Equatable, Sendable {
    public var entries: [NameGlossaryEntry]
    public init(entries: [NameGlossaryEntry]) { self.entries = entries }
    public static var standard: Self { Self(entries: LocalNameSuggester.defaultDictionary) }

    public func validated() throws -> Self {
        guard entries.count <= 100 else { throw GlossaryError.message("词典最多支持 100 条转换。") }
        var seen = Set<String>()
        for entry in entries {
            guard !entry.source.isEmpty, entry.source.utf8.count <= 64,
                  entry.source == entry.source.trimmingCharacters(in: .whitespacesAndNewlines),
                  !entry.source.contains("="), !entry.source.contains("/"), !entry.source.contains("\\"),
                  entry.source.unicodeScalars.allSatisfy({ ![.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory) }),
                  seen.insert(entry.source.lowercased()).inserted else {
                throw GlossaryError.message("原词须为不重复的短语，最多 64 字节，不能含等号、路径或控制字符。")
            }
            guard LocalNameSuggester.validatedDescription(entry.target) == entry.target else {
                throw GlossaryError.message("英文转换须为简短的英文 snake_case，不含日期、后缀或命令字段：" + entry.source)
            }
        }
        return self
    }

    private enum GlossaryError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case .message(let text): return text } }
    }
}
