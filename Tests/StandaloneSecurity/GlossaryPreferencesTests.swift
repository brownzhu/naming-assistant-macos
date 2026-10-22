import Foundation

extension SecurityRegression {
    static func glossaryPreferencesTests() async {
        func result(_ input: String, _ preferences: NameGlossaryPreferences) -> LocalNameSuggestionResult {
            LocalNameSuggester.dictionarySuggestion(basename: input, glossary: preferences)
        }
        test("custom glossary: defaults validate and round-trip") {
            let value = try NameGlossaryPreferences.standard.validated()
            let restored = try JSONDecoder().decode(NameGlossaryPreferences.self, from: JSONEncoder().encode(value))
            try check(restored == value, "Dictionary changed during encoding")
        }
        test("custom glossary: override built-in phrase") {
            let value = NameGlossaryPreferences(entries: [.init(source: "会议记录", target: "meeting_minutes")])
            try check(result("会议记录", try value.validated()).suggestion?.description == "meeting_minutes", "Override ignored")
        }
        test("custom glossary: replacements never cascade") {
            let value = NameGlossaryPreferences(entries: [.init(source: "alpha", target: "beta"), .init(source: "beta", target: "gamma")])
            try check(result("alpha", value).suggestion?.description == "beta", "Generated target was translated again")
        }
        test("custom glossary: deleted built-in stays removed") {
            try check(result("会议记录", .init(entries: [])).status == .needsManualEnglish, "Deleted term silently returned")
        }
        test("custom glossary: unknown text cannot be dropped") {
            let value = NameGlossaryPreferences(entries: [.init(source: "会议", target: "meeting")])
            try check(result("会议未知词", value).status == .needsManualEnglish, "Unknown Chinese was lost")
        }
        test("custom glossary: English keys respect boundaries") {
            let value = NameGlossaryPreferences(entries: [.init(source: "art", target: "creative_work")])
            try check(result("partial", value).suggestion?.description == "partial", "Substring replaced")
            try check(result("art", value).suggestion?.description == "creative_work", "Exact term missed")
        }
        test("custom glossary: user regex characters are literals") {
            let value = NameGlossaryPreferences(entries: [.init(source: "a.*", target: "literal_pattern")])
            try check(result("apple", value).suggestion?.description == "apple", "User pattern executed")
        }
        test("custom glossary: invalid targets and duplicate keys rejected") {
            for value in [NameGlossaryPreferences(entries: [.init(source: "x", target: "../../outside")]),
                          .init(entries: [.init(source: "x", target: "sudo_rm")]),
                          .init(entries: [.init(source: "x", target: "hello_world"), .init(source: "X", target: "different_word")]),
                          .init(entries: [.init(source: "bad\u{202E}", target: "hello_world")])] {
                try mustThrow { _ = try value.validated() }
                try check(result("x", value).status == .invalidInput, "Invalid dictionary used")
            }
        }
        test("custom glossary: bounded rules and source lengths") {
            try mustThrow { _ = try NameGlossaryPreferences(entries: (0..<101).map { .init(source: "term\($0)", target: "hello_world") }).validated() }
            try mustThrow { _ = try NameGlossaryPreferences(entries: [.init(source: String(repeating: "a", count: 65), target: "hello_world")]).validated() }
        }
        let explicit = await LocalNameSuggester().suggest(basename: "会议", useOnDeviceModel: true,
                                                        glossary: .init(entries: [.init(source: "会议", target: "meeting_minutes")]))
        test("custom glossary: explicit rule takes priority over model") {
            try check(explicit.suggestion?.source == .localDictionary && explicit.suggestion?.description == "meeting_minutes", "Custom term did not take priority")
        }
    }
}
