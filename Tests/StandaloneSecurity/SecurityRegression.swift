import Foundation
import Darwin

struct ReviewFailure: Error, CustomStringConvertible { let description: String }

@main @MainActor struct SecurityRegression {
    static var passed = 0
    static var failed = 0
    static func check(_ condition: Bool, _ description: String) throws {
        guard condition else { throw ReviewFailure(description: description) }
    }
    static func mustThrow(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw ReviewFailure(description: "Expected rejection")
    }
    static func test(_ name: String, _ body: () throws -> Void) {
        do { try body(); passed += 1; print("PASS \(name)") }
        catch { failed += 1; print("FAIL \(name): \(error)") }
    }
    static func namingTests() {
        let profile = NamingProfile()
        func name(_ ext: String = "", _ description: String = "CEM EIT proof", date: Date? = nil, version: Int? = nil) throws -> String {
            try profile.suggestName(for: NamingRequest(date: date, category: .research, description: description, version: version, fileExtension: ext))
        }
        test("naming: timestamp and description use underscores") {
            let date = ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z")!
            let value = try name("PDF", "CEM EIT proof", date: date, version: 1)
            try check(value == "2026_10_20_research_cem_eit_proof_v01.PDF", value)
        }
        test("naming: explicit absence of date stays undated") {
            let value = try name()
            try check(value == "undated_research_cem_eit_proof", value)
        }
        test("naming: Berlin timezone determines calendar day") {
            let date = ISO8601DateFormatter().date(from: "2026-10-19T23:30:00Z")!
            let value = try name("pdf", date: date)
            try check(value.hasPrefix("2026_10_20_"), value)
        }
        test("naming: compound extension is preserved") {
            try check(try name(".nii.gz").hasSuffix(".nii.gz"), "Compound extension lost")
        }
        test("naming: no traversal component can escape through description") {
            let value = try name("pdf", "../../evil\\outside:$(whoami)")
            try check(!value.contains("/") && !value.contains("\\") && !value.contains(":"), value)
        }
        test("naming: malformed extension is rejected") {
            for ext in ["../pdf", "a/b", "a:b", "a\\b", "a\u{0}b", "a\nb", "a\u{202E}exe", "..pdf", "pdf.", ".", "pdf ", " pdf"] {
                try mustThrow { _ = try name(ext) }
            }
        }
        test("naming: non-finite and out-of-range dates are rejected") {
            for seconds in [Double.nan, .infinity, -.infinity, 253402300800.0, -62167219200.0] {
                try mustThrow { _ = try name(date: Date(timeIntervalSince1970: seconds)) }
            }
        }
        test("naming: invalid timezone rejected") {
            try mustThrow { _ = try NamingProfile(timeZoneIdentifier: "bad/zone").suggestName(for: NamingRequest(category: .life, description: "x")) }
        }
        test("naming: zero and negative version rejected") {
            try mustThrow { _ = try name(version: 0) }
            try mustThrow { _ = try name(version: -1) }
        }
        test("naming: empty and non-English descriptions rejected") {
            try mustThrow { _ = try name("pdf", "..__") }
            try mustThrow { _ = try name("pdf", "中文") }
        }
        test("naming: output longer than a filename rejected") {
            try mustThrow { _ = try name("pdf", String(repeating: "a", count: 256)) }
        }
        test("naming: folder cannot carry a file extension") {
            try mustThrow { _ = try profile.suggestName(for: NamingRequest(category: .research, description: "x", kind: .projectFolder, fileExtension: "pdf")) }
        }
    }
    static func main() async throws {
        namingTests()
        folderCategoryTests()
        await safetyTests()
        await localSuggesterTests()
        await folderAssistTests()
        print("RESULT \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
