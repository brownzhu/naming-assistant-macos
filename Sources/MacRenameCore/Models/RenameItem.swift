import Foundation

/// Represents a single file or folder to be renamed.
@Observable
public final class RenameItem: Identifiable, @unchecked Sendable {
    public let id: UUID
    public let url: URL
    public let originalName: String
    public let isFolder: Bool
    public let depth: Int

    public var newName: String?
    public var isSelected: Bool
    public var status: RenameStatus

    public init(url: URL, isFolder: Bool, depth: Int) {
        self.id = UUID()
        self.url = url
        self.originalName = url.lastPathComponent
        self.isFolder = isFolder
        self.depth = depth
        self.newName = nil
        self.isSelected = true
        self.status = .initial
    }

    /// The directory containing this item.
    public var parentPath: String {
        url.deletingLastPathComponent().path
    }

    /// The full path that would result from renaming.
    public var projectedURL: URL? {
        guard let newName else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(newName)
    }

    /// The filename stem (without extension). For folders, returns the full name.
    public var stem: String {
        if isFolder { return originalName }
        let ext = (originalName as NSString).pathExtension
        if ext.isEmpty { return originalName }
        return (originalName as NSString).deletingPathExtension
    }

    /// The file extension (without dot). Empty for folders.
    public var fileExtension: String {
        if isFolder { return "" }
        return (originalName as NSString).pathExtension
    }

    /// Retrieves a file timestamp based on the given source.
    public func fileTime(for source: TimeSource) -> Date? {
        let keys: [URLResourceKey]
        switch source {
        case .creation: keys = [.creationDateKey]
        case .modification: keys = [.contentModificationDateKey]
        case .access: keys = [.contentAccessDateKey]
        }
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
            return nil
        }
        switch source {
        case .creation: return values.creationDate
        case .modification: return values.contentModificationDate
        case .access: return values.contentAccessDate
        }
    }

    /// Reset to initial state for a new preview computation.
    public func reset() {
        newName = nil
        status = .initial
    }
}
