import Foundation
import MacRenameCore

@MainActor
enum NamingPreferencesStore {
    private static let categoryKey = "naming.categories.v1"
    private static let glossaryKey = "naming.glossary.v1"
    static func categories() -> NamingCategoryPreferences {
        if let data = UserDefaults.standard.data(forKey: categoryKey), data.count <= 100_000,
           let decoded = try? JSONDecoder().decode(NamingCategoryPreferences.self, from: data),
           let valid = try? decoded.validated() { return valid }
        return .standard
    }
    static func glossary() -> NameGlossaryPreferences {
        if let data = UserDefaults.standard.data(forKey: glossaryKey), data.count <= 100_000,
           let decoded = try? JSONDecoder().decode(NameGlossaryPreferences.self, from: data),
           let valid = try? decoded.validated() { return valid }
        return .standard
    }
    static func save(_ preferences: NamingCategoryPreferences) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(preferences.validated()), forKey: categoryKey)
    }
    static func save(_ preferences: NameGlossaryPreferences) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(preferences.validated()), forKey: glossaryKey)
    }
}
