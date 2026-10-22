import Foundation

extension SecurityRegression {
    static func categoryPreferencesTests() {
        func option(_ token: String = "custom", id: String = "custom", label: String = "自定义", keywords: [String] = ["budget"], visible: Bool = true) -> NamingCategoryOption {
            NamingCategoryOption(id: id, label: label, token: token, keywords: keywords, isVisible: visible)
        }
        func one(_ value: NamingCategoryOption) -> NamingCategoryPreferences {
            NamingCategoryPreferences(options: [value], defaultID: value.id)
        }

        test("category preferences: standard retains five editable Chinese categories and default") {
            let standard = NamingCategoryPreferences.standard
            try check(try standard.validated() == standard, "Standard preferences were changed by validation")
            try check(standard.options.map(\.token) == ["life", "research", "engineering", "learning", "admin"], "Standard category tokens changed")
            try check(standard.options.map(\.label) == ["生活", "科研", "工程", "学习", "管理"], "Chinese labels changed")
            try check(standard.options.allSatisfy { $0.id == $0.token && !$0.keywords.isEmpty && $0.isVisible }, "Missing default hints or visibility")
            try check(standard.defaultID == "research" && standard.visibleOptions.count == 5, "Incorrect standard selection")
            let restored = try JSONDecoder().decode(NamingCategoryPreferences.self, from: JSONEncoder().encode(standard))
            try check(restored == standard, "Preference Codable round-trip changed data")
        }
        test("category preferences: limits accept one and twenty categories, reject zero and twenty-one") {
            try check(try one(option()).validated().options.count == 1, "One custom category rejected")
            let twenty = (1...20).map { option("custom_\($0)", id: "id_\($0)") }
            _ = try NamingCategoryPreferences(options: twenty, defaultID: "id_1").validated()
            try mustThrow { _ = try NamingCategoryPreferences(options: [], defaultID: "research").validated() }
            try mustThrow { _ = try NamingCategoryPreferences(options: twenty + [option("extra", id: "extra")], defaultID: "id_1").validated() }
        }
        test("category preferences: hidden choices retain edits but cannot be default or recommended") {
            var value = NamingCategoryPreferences.standard
            value.options[4].isVisible = false
            _ = try value.validated()
            try check(value.options.count == 5 && value.visibleOptions.count == 4 && value.options[4].keywords.contains("invoice"), "Hiding deleted configuration")
            try check(value.recommendation(for: "invoice") == nil, "Hidden category was recommended")
            value.defaultID = "admin"
            try mustThrow { _ = try value.validated() }
            value.defaultID = "missing"
            try mustThrow { _ = try value.validated() }
            value.options = value.options.map { var hidden = $0; hidden.isVisible = false; return hidden }
            try mustThrow { _ = try value.validated() }
        }
        test("category preferences: duplicate identifiers and tokens reject even hidden rows") {
            try mustThrow {
                _ = try NamingCategoryPreferences(options: [option(), option("other", visible: false)], defaultID: "custom").validated()
            }
            try mustThrow {
                _ = try NamingCategoryPreferences(options: [option(), option(id: "other", visible: false)], defaultID: "custom").validated()
            }
            for badID in ["", " ", "bad\nidentifier", "bad\u{202E}identifier", String(repeating: "a", count: 129)] {
                try mustThrow { _ = try one(option(id: badID)).validated() }
            }
        }
        test("category preferences: filename tokens reject traversal, regex, Unicode and ambiguous underscores") {
            for token in ["", "A", "1a", "_a", "a_", "a__b", "../x", "a/b", "a\\b", "a:b", "a.b", "a-b", "a b", "a\n", "a\u{202E}", "café", "科研", "a.*", "(a|b)", String(repeating: "a", count: 25)] {
                try mustThrow { _ = try one(option(token)).validated() }
            }
            for token in ["a", "a1", "custom_1", "data_science", String(repeating: "a", count: 24)] {
                _ = try one(option(token)).validated()
            }
        }
        test("category preferences: display labels count characters and reject invisible controls") {
            _ = try one(option(label: String(repeating: "研", count: 32))).validated()
            for label in ["", "   ", String(repeating: "研", count: 33), "a\n", "a\t", "a\u{200B}", "a\u{2028}", "a\u{202E}"] {
                try mustThrow { _ = try one(option(label: label)).validated() }
            }
        }
        test("category preferences: keywords enforce count and UTF8 byte boundaries") {
            _ = try one(option(keywords: (1...30).map { "keyword\($0)" })).validated()
            _ = try one(option(keywords: [String(repeating: "a", count: 64), String(repeating: "研", count: 21)])).validated()
            _ = try one(option(keywords: [])).validated()
            try mustThrow { _ = try one(option(keywords: (1...31).map { "keyword\($0)" })).validated() }
            for keyword in ["", "  ", "x\n", "x\u{2066}", "x\u{2029}", String(repeating: "a", count: 65), String(repeating: "研", count: 22)] {
                try mustThrow { _ = try one(option(keywords: [keyword])).validated() }
            }
        }
        test("category preferences: standard hints are conservative and retain five distinct meanings") {
            let standard = NamingCategoryPreferences.standard
            for (text, category) in [("invoiceDraft", "admin"), ("Swift compiler", "engineering"), ("study_notes", "learning"), ("cem_eit", "research"), ("旅行计划", "life")] {
                try check(standard.recommendation(for: text)?.id == category, "Missing clear hint: \(text)")
            }
            for text in ["test", "unknown_folder", "invoiceable", "codec", "coursework", "python3", "invoiceé", "invoice\u{301}", "paper_code", "实验课程"] {
                try check(standard.recommendation(for: text) == nil, "Unsupported or tied text received a recommendation: \(text)")
            }
        }
        test("category preferences: edited keywords replace previous meanings without changing names") {
            var value = one(option("finance", keywords: ["budget", "预算"]))
            value.options[0].label = "预算资料"
            _ = try value.validated()
            try check(value.recommendation(for: "预算安排")?.token == "finance", "Custom CJK literal missing")
            try check(value.recommendation(for: "BUDGET_notes")?.label == "预算资料", "Custom English hint missing")
            value.options[0].keywords = ["recipe"]
            try check(value.recommendation(for: "budget") == nil && value.recommendation(for: "recipe")?.token == "finance", "Old keywords survived replacement")
        }
        test("category preferences: user patterns are literals rather than executable regular expressions") {
            let literal = one(option(keywords: ["invoice.*", "c++", "(budget)"]))
            try check(literal.recommendation(for: "invoice_draft") == nil, "User regex syntax executed")
            try check(literal.recommendation(for: "my_c++_notes")?.id == "custom", "Literal programming keyword lost")
            try check(literal.recommendation(for: "invoice.*")?.id == "custom", "Literal regex-looking text was not treated literally")
        }
        test("category preferences: duplicate keyword variants and repeated input cannot inflate evidence") {
            let value = NamingCategoryPreferences(options: [
                option("finance", id: "finance", keywords: ["invoice", "INVOICE", " invoice "]),
                option("holiday", id: "holiday", keywords: ["travel"]),
            ], defaultID: "finance")
            try check(value.recommendation(for: "invoice_invoice_travel") == nil, "Repeated or case-variant keywords outvoted a tie")
            var stronger = value
            stronger.options[0].keywords.append("budget")
            try check(stronger.recommendation(for: "invoice_budget_travel")?.id == "finance", "Distinct evidence lost")
        }
        test("category preferences: invalid configurations and excessive/control input have no recommendation") {
            var invalid = NamingCategoryPreferences.standard
            invalid.defaultID = "missing"
            try check(invalid.recommendation(for: "invoice") == nil, "Invalid configuration used")
            for text in ["", "invoice\n", "invoice\u{202E}", "invoice_" + String(repeating: "a", count: 248)] {
                try check(NamingCategoryPreferences.standard.recommendation(for: text) == nil, "Unsafe input accepted")
            }
            try check(NamingCategoryPreferences.standard.recommendation(for: "invoice_" + String(repeating: "a", count: 247))?.id == "admin", "255-byte input rejected")
        }
        test("custom naming: token override preserves dates, extensions, versions and legacy Codable") {
            let request = NamingRequest(date: ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z"), category: .research, description: "Meeting Notes", version: 2, fileExtension: ".nii.GZ")
            let profile = NamingProfile()
            try check(try profile.suggestName(for: request, categoryToken: "data_science") == "2026_10_20_data_science_meeting_notes_v02.nii.GZ", "Custom token altered other naming fields")
            try check(try profile.suggestName(for: request) == "2026_10_20_research_meeting_notes_v02.nii.GZ", "Legacy naming changed")
            let data = try JSONEncoder().encode(request)
            try check(try JSONDecoder().decode(NamingRequest.self, from: data) == request, "Legacy request Codable changed")
            let folder = NamingRequest(category: .research, description: "test", kind: .projectFolder)
            try check(try profile.suggestName(for: folder, categoryToken: "finance") == "undated_finance_test", "Custom token invented folder date or version")
        }
        test("custom naming: invalid category tokens cannot bypass naming validation") {
            let request = NamingRequest(category: .life, description: "test")
            for token in ["../escape", "UPPER", "a__b", "a_", "1a", "a.*", "科研", String(repeating: "a", count: 25)] {
                try mustThrow { _ = try NamingProfile().suggestName(for: request, categoryToken: token) }
            }
            var tooLong = request
            tooLong.description = String(repeating: "a", count: 240)
            try mustThrow { _ = try NamingProfile().suggestName(for: tooLong, categoryToken: "data_science") }
        }
        test("custom recognition: additional literal tokens are opt-in and cannot inject patterns") {
            let custom = "2026_10_data_science_test"
            try check(!NamingProfile.matchesStandardStem(custom, kind: .projectFolder), "Unknown token recognized without opt-in")
            try check(NamingProfile.matchesStandardStem(custom, kind: .projectFolder, categoryTokens: ["data_science"]), "Custom token not recognized")
            try check(NamingProfile.matchesStandardStem("undated_admin_test", kind: .projectFolder, categoryTokens: ["data_science"]), "Legacy category recognition lost")
            try check(!NamingProfile.matchesStandardStem("2026_10_anything_test", kind: .projectFolder, categoryTokens: [".*", "(anything|other)"]), "Regex token executed")
            try check(!NamingProfile.matchesStandardStem("2026_10_data_science_test", kind: .file, categoryTokens: ["data_science"]), "Folder month mistaken for file day")
        }
    }
}
