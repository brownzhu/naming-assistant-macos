import Foundation

/// Enumerates files and folders from given URLs, optionally recursing into subdirectories.
public enum FileEnumerator {

    /// Creates `RenameItem` instances from the given URLs.
    /// If a URL points to a directory and `recursive` is true, its contents are enumerated.
    /// Items are returned in a stable order: directories first (for depth-first rename safety),
    /// then files, sorted alphabetically within each group at each level.
    public static func enumerate(
        urls: [URL],
        recursive: Bool = true
    ) -> [RenameItem] {
        var items: [RenameItem] = []
        let fm = FileManager.default

        for url in urls {
            let standardized = url.standardizedFileURL

            // Skip symlinks: we don't want to rename the link itself (and
            // surprise the user) or follow it into an unexpected directory.
            if isSymlink(standardized) {
                continue
            }

            var isDir: ObjCBool = false

            guard fm.fileExists(atPath: standardized.path, isDirectory: &isDir) else {
                continue
            }

            if isDir.boolValue {
                let folderItem = RenameItem(url: standardized, isFolder: true, depth: 0)
                items.append(folderItem)

                if recursive {
                    let children = enumerateDirectory(
                        standardized,
                        baseDepth: 1,
                        fileManager: fm
                    )
                    items.append(contentsOf: sorted(children))
                }
            } else {
                let fileItem = RenameItem(url: standardized, isFolder: false, depth: 0)
                items.append(fileItem)
            }
        }

        return items
    }

    /// Stable sort matching the documented contract: folders first (for
    /// depth-first rename safety), then files, alphabetical within each group
    /// at each directory level.
    private static func sorted(_ items: [RenameItem]) -> [RenameItem] {
        items.sorted { lhs, rhs in
            let lhsParent = lhs.url.deletingLastPathComponent().path
            let rhsParent = rhs.url.deletingLastPathComponent().path
            if lhsParent != rhsParent { return lhsParent < rhsParent }
            if lhs.isFolder != rhs.isFolder { return lhs.isFolder && !rhs.isFolder }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    private static func enumerateDirectory(
        _ directoryURL: URL,
        baseDepth: Int,
        fileManager fm: FileManager
    ) -> [RenameItem] {
        var items: [RenameItem] = []

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return items
        }

        while let itemURL = enumerator.nextObject() as? URL {
            let resourceValues = try? itemURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )

            // Skip symlinks. Renaming a symlink only renames the link, but a
            // symlink in a user's tree may point anywhere — and if the
            // enumerator follows it for traversal, we could end up walking
            // into unexpected territory.
            if resourceValues?.isSymbolicLink == true {
                continue
            }

            let isDir = resourceValues?.isDirectory ?? false

            // Depth is based on path components relative to the base directory
            let relativePath = itemURL.path.dropFirst(directoryURL.path.count)
            let depth = baseDepth + relativePath.components(separatedBy: "/").filter { !$0.isEmpty }.count - 1

            let item = RenameItem(url: itemURL, isFolder: isDir, depth: depth)
            items.append(item)
        }

        return items
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }
}
