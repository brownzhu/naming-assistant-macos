import Foundation

/// Thread-safe cache for extracted metadata patterns, keyed by file URL.
public actor MetadataCache {
    private var cache: [URL: [String: String]] = [:]

    public init() {}

    /// Gets metadata patterns for a URL, extracting them if not cached.
    public func patterns(
        for url: URL,
        exif: Bool,
        xmp: Bool
    ) -> [String: String] {
        if let cached = cache[url] {
            return cached
        }
        let extracted = MetadataExtractor.extractPatterns(from: url, exif: exif, xmp: xmp)
        cache[url] = extracted
        return extracted
    }

    /// Clears the entire cache.
    public func clear() {
        cache.removeAll()
    }

    /// Removes a single entry from the cache.
    public func invalidate(url: URL) {
        cache.removeValue(forKey: url)
    }
}
