import Foundation

extension SecurityRegression {
    static func folderCategoryTests() {
        test("folder category: clear terms suggest each category") {
            for (text, expected) in [
                ("cem_eit_uniqueness", NamingCategory.research),
                ("Swift compiler", .engineering),
                ("study_notes", .learning),
                ("invoice", .admin),
                ("travel_plan", .life),
            ] {
                try check(FolderCategorySuggester.recommend(for: text)?.category == expected,
                          "No appropriate category for \(text)")
            }
        }
        test("folder category: neutral names do not fabricate evidence") {
            for text in ["test", "project", "notes", "report", "draft", "unknown_folder", "2026_10_22", "未收录的名字"] {
                try check(FolderCategorySuggester.recommend(for: text) == nil,
                          "Neutral name received a confident category: \(text)")
            }
        }
        test("folder category: token boundaries avoid English substring matches") {
            for text in ["invoiceable", "codec", "buildings", "travelogue", "coursework", "uniquenesses", "python3"] {
                try check(FolderCategorySuggester.recommend(for: text) == nil,
                          "Substring or technical suffix was treated as a whole keyword: \(text)")
            }
        }
        test("folder category: English case and common separators preserve evidence") {
            for text in ["INVOICE", "Invoice Draft", "invoice-draft", "invoice_draft", "invoiceDraft"] {
                try check(FolderCategorySuggester.recommend(for: text)?.category == .admin,
                          "Equivalent word boundary lost: \(text)")
            }
        }
        test("folder category: known Chinese and mixed technical names are hints") {
            for (text, expected) in [
                ("实验结果", NamingCategory.research),
                ("Swift代码", .engineering),
                ("课程笔记", .learning),
                ("报销材料", .admin),
                ("旅行计划", .life),
            ] {
                try check(FolderCategorySuggester.recommend(for: text)?.category == expected,
                          "Known phrase not recognized: \(text)")
            }
        }
        test("folder category: tied evidence remains a user choice") {
            for text in ["python_course", "invoice_travel", "paper_code", "实验课程"] {
                try check(FolderCategorySuggester.recommend(for: text) == nil,
                          "Tied categories resolved without evidence: \(text)")
            }
        }
        test("folder category: repeated words cannot defeat ambiguity") {
            try check(FolderCategorySuggester.recommend(for: "invoice_invoice_invoice_travel") == nil,
                      "Repeated words inflated the score")
        }
        test("folder category: stronger distinct evidence wins and is explained") {
            let value = FolderCategorySuggester.recommend(for: "paper_cem_invoice")
            try check(value?.category == .research && value?.matchedKeywords == ["cem", "paper"],
                      "Distinct evidence or explanation was lost")
        }
        test("folder category: control and invisible characters reject input") {
            for suffix in ["\u{0}", "\n", "\t", "\u{7F}", "\u{202E}", "\u{2066}", "\u{200B}", "\u{2028}"] {
                try check(FolderCategorySuggester.recommend(for: "invoice" + suffix) == nil,
                          "Control/format character accepted")
            }
        }
        test("folder category: input has a UTF8 byte limit") {
            try check(FolderCategorySuggester.recommend(for: "") == nil, "Empty input accepted")
            let boundary = "invoice_" + String(repeating: "a", count: 247)
            try check(boundary.utf8.count == 255 && FolderCategorySuggester.recommend(for: boundary)?.category == .admin,
                      "Valid boundary input rejected")
            try check(FolderCategorySuggester.recommend(for: boundary + "a") == nil, "Byte limit exceeded")
            try check(FolderCategorySuggester.recommend(for: "发票" + String(repeating: "中", count: 84)) == nil,
                      "Non-ASCII bytes bypassed limit")
        }
    }
}
