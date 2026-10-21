import Foundation

/// Persisted application settings backed by UserDefaults.
@Observable
public final class AppSettings {
    private let defaults: UserDefaults

    /// All UserDefaults keys this class persists. `resetAll()` iterates
    /// `Key.all`, so adding a new persisted property requires adding its
    /// name here too — there's a single source of truth.
    private enum Key {
        static let persistState = "persistState"
        static let maxMRUSize = "maxMRUSize"
        static let defaultFlags = "defaultFlags"
        static let lastSearchTerm = "lastSearchTerm"
        static let lastReplaceTerm = "lastReplaceTerm"
        static let searchMRU = "searchMRU"
        static let replaceMRU = "replaceMRU"

        static let all: [String] = [
            persistState, maxMRUSize, defaultFlags,
            lastSearchTerm, lastReplaceTerm,
            searchMRU, replaceMRU,
        ]
    }

    /// MRU lists are stored properties (not computed pass-throughs) so that
    /// `@Observable`'s change tracking fires when they're mutated and any
    /// SwiftUI view binding to them re-renders. Persistence happens in
    /// didSet. Other settings can remain computed because nothing observes
    /// them in the UI without going through an `AppViewModel` mirror.
    public var searchMRU: [String] = [] {
        didSet { defaults.set(searchMRU, forKey: Key.searchMRU) }
    }
    public var replaceMRU: [String] = [] {
        didSet { defaults.set(replaceMRU, forKey: Key.replaceMRU) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Hydrate the @Observable mirrors from disk. didSet does not fire
        // during init, so this doesn't write back redundantly.
        self.searchMRU = defaults.stringArray(forKey: Key.searchMRU) ?? []
        self.replaceMRU = defaults.stringArray(forKey: Key.replaceMRU) ?? []
    }

    public var persistState: Bool {
        get { defaults.bool(forKey: Key.persistState) }
        set { defaults.set(newValue, forKey: Key.persistState) }
    }

    public var maxMRUSize: Int {
        get {
            let val = defaults.integer(forKey: Key.maxMRUSize)
            return val > 0 ? val : 10
        }
        set { defaults.set(newValue, forKey: Key.maxMRUSize) }
    }

    public var defaultFlags: UInt32 {
        get { UInt32(defaults.integer(forKey: Key.defaultFlags)) }
        set { defaults.set(Int(newValue), forKey: Key.defaultFlags) }
    }

    public var lastSearchTerm: String? {
        get { defaults.string(forKey: Key.lastSearchTerm) }
        set { defaults.set(newValue, forKey: Key.lastSearchTerm) }
    }

    public var lastReplaceTerm: String? {
        get { defaults.string(forKey: Key.lastReplaceTerm) }
        set { defaults.set(newValue, forKey: Key.lastReplaceTerm) }
    }

    /// Pushes an entry to the front of the MRU list, dedup-ing and capping at `maxMRUSize`.
    public func pushSearchMRU(_ term: String) {
        guard !term.isEmpty else { return }
        searchMRU = prepend(term, to: searchMRU)
    }

    public func pushReplaceMRU(_ term: String) {
        guard !term.isEmpty else { return }
        replaceMRU = prepend(term, to: replaceMRU)
    }

    public func clearSearchMRU() {
        searchMRU = []
    }

    public func clearReplaceMRU() {
        replaceMRU = []
    }

    /// Wipes every persisted setting. Used by the "Reset Quick Rename…"
    /// app-menu item. Also clears the in-memory MRU mirrors so any SwiftUI
    /// view bound to them re-renders immediately.
    public func resetAll() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
        searchMRU = []
        replaceMRU = []
    }

    private func prepend(_ term: String, to list: [String]) -> [String] {
        var next = list.filter { $0 != term }
        next.insert(term, at: 0)
        if next.count > maxMRUSize { next.removeLast(next.count - maxMRUSize) }
        return next
    }
}
