import Foundation

/// Central orchestrator for the rename pipeline.
/// Manages items, computes preview names, and executes file renames.
/// Matches PowerRename's CPowerRenameManager + DoRename flow.
@Observable
public final class RenameEngine: @unchecked Sendable {
    public var searchTerm: String = ""
    public var replaceTerm: String = ""
    public var flags: RenameFlags = []
    public var items: [RenameItem] = []

    private let metadataCache = MetadataCache()

    public init() {}

    // MARK: - Item Management

    /// Adds files/folders from the given URLs.
    public func addItems(urls: [URL], recursive: Bool = true) {
        let newItems = FileEnumerator.enumerate(urls: urls, recursive: recursive)
        items.append(contentsOf: newItems)
    }

    /// Removes all items and resets state.
    public func clearItems() {
        items.removeAll()
    }

    // MARK: - Preview Computation

    /// Computes new names for all items based on current search/replace/flags.
    /// This is the "regex phase" — no files are modified.
    public func computePreview() async {
        // Reset all items except those already renamed on disk — resetting those
        // would cause the next rename pass to try to move files that no longer
        // exist at the original URL.
        for item in items where item.status != .renamed {
            item.reset()
        }

        guard !searchTerm.isEmpty else { return }

        var enumIndex = 0

        for item in items {
            if item.status == .renamed { continue }

            let shouldProcess = shouldProcessItem(item)

            if !shouldProcess {
                item.status = .excluded
                continue
            }

            await processItem(item, enumIndex: &enumIndex)
        }

        // Post-processing: detect duplicate new names within the same directory
        detectDuplicates()
    }

    /// Marks items as `.nameAlreadyExists` if multiple items in the same
    /// directory would end up with the same new name. Comparison is
    /// case-insensitive to match the default APFS/HFS+ behavior — `Photo.jpg`
    /// and `photo.jpg` collide on a stock macOS volume.
    private func detectDuplicates() {
        // Group items by parent directory
        var byDirectory: [String: [RenameItem]] = [:]
        for item in items where item.status == .shouldRename {
            byDirectory[item.parentPath, default: []].append(item)
        }

        for (directory, dirItems) in byDirectory {
            // Count names already taken in this directory by items that
            // aren't being renamed: existing files (not in our list) and
            // items the user excluded or unselected.
            var counts: [String: Int] = [:]
            for item in items
                where item.parentPath == directory
                && (item.status != .shouldRename || !item.isSelected) {
                counts[item.originalName.lowercased(), default: 0] += 1
            }

            // Add the proposed new names from items in this directory.
            for item in dirItems {
                guard let newName = item.newName else { continue }
                counts[newName.lowercased(), default: 0] += 1
            }

            // Any item whose target name has count > 1 is colliding — either
            // with another rename in the batch or with an existing file.
            for item in dirItems {
                guard let newName = item.newName else { continue }
                if (counts[newName.lowercased()] ?? 0) > 1 {
                    item.status = .nameAlreadyExists
                }
            }
        }
    }

    /// Processes a single item through the full rename pipeline.
    /// Matches Renaming.cpp DoRename() flow.
    private func processItem(_ item: RenameItem, enumIndex: inout Int) async {
        // 1. Determine source name based on scoping flags
        let sourceName = extractSourceName(from: item)

        // 2. Build the replacement template with token expansion
        var currentReplace = replaceTerm

        // 2a. Expand enumeration and randomizer tokens
        currentReplace = TokenExpander.expandInlineTokens(
            currentReplace,
            flags: flags,
            enumIndex: enumIndex
        )

        // 2b. Expand date/time tokens if a time source is active
        if let timeSource = flags.timeSource,
           let fileDate = item.fileTime(for: timeSource),
           DateTimeToken.containsTokens(in: replaceTerm) {
            currentReplace = TokenExpander.expandDateTimeTokens(currentReplace, date: fileDate)
        }

        // 2c. Expand metadata tokens if metadata source is active
        if flags.usesMetadata && MetadataToken.containsTokens(in: replaceTerm) {
            let ext = item.fileExtension.lowercased()
            if !item.isFolder && MetadataPatterns.supportsMetadata(fileExtension: ext) {
                let patterns = await metadataCache.patterns(
                    for: item.url,
                    exif: flags.contains(.metadataEXIF),
                    xmp: flags.contains(.metadataXMP)
                )
                currentReplace = TokenExpander.expandMetadataTokens(currentReplace, patterns: patterns)
            }
        }

        // 3. Perform search/replace
        let result = SearchReplace.replace(
            in: sourceName,
            searchTerm: searchTerm,
            replaceTerm: currentReplace,
            flags: flags
        )

        // The enumeration counter advances per match, not per visible change.
        // This keeps `(.*) → NewFile-${start=1}` producing distinct indices even
        // when one of the files already matches the target name.
        if result.matched {
            enumIndex += 1
        }

        var newName = result.output

        // 4. If no match but text transform is active, apply transform to source
        if newName == nil && flags.textTransform != nil {
            newName = sourceName
        }

        guard var computedName = newName else {
            item.status = .unchanged
            return
        }

        // 5. Reassemble full filename from scoped part
        computedName = reassembleName(computedName, for: item)

        // 6. Trim whitespace and trailing dots
        computedName = FileValidator.trimFilename(computedName)

        // 7. Apply text transformation
        if let transform = flags.textTransform {
            computedName = CaseTransform.apply(transform, to: computedName, flags: flags)
        }

        // 8. Check if name actually changed
        if computedName == item.originalName {
            item.status = .unchanged
            return
        }

        // 9. Validate
        let validationStatus = FileValidator.validate(
            newName: computedName,
            parentPath: item.parentPath,
            isFolder: item.isFolder
        )

        item.newName = computedName
        item.status = validationStatus
    }

    // MARK: - File Operations

    /// Executes the rename operation on all items with status `.shouldRename`.
    /// Uses `FileRenamer` for atomic operations with automatic rollback on failure.
    public func executeRename() async throws -> [RenamePair] {
        try FileRenamer.execute(items: items)
    }

    /// Undoes a set of renames by reversing each pair.
    public func undoRenames(_ pairs: [RenamePair]) throws {
        try FileRenamer.undo(pairs)
    }

    // MARK: - Helpers

    /// Determines whether an item should be processed based on exclusion flags.
    private func shouldProcessItem(_ item: RenameItem) -> Bool {
        if flags.contains(.excludeFolders) && item.isFolder { return false }
        if flags.contains(.excludeFiles) && !item.isFolder { return false }
        if flags.contains(.excludeSubfolders) && item.depth > 0 { return false }
        // extensionOnly doesn't apply to folders
        if flags.contains(.extensionOnly) && item.isFolder { return false }
        if !item.isSelected { return false }
        return true
    }

    /// Extracts the portion of the filename to search within, based on scoping flags.
    private func extractSourceName(from item: RenameItem) -> String {
        if item.isFolder {
            return item.originalName
        }

        if flags.contains(.nameOnly) {
            return item.stem
        }

        if flags.contains(.extensionOnly) {
            return item.fileExtension
        }

        return item.originalName
    }

    /// Reassembles the full filename after search/replace on a scoped part.
    private func reassembleName(_ processedPart: String, for item: RenameItem) -> String {
        if item.isFolder {
            return processedPart
        }

        let ext = item.fileExtension

        if flags.contains(.nameOnly) && !ext.isEmpty {
            return "\(processedPart).\(ext)"
        }

        if flags.contains(.extensionOnly) && !ext.isEmpty {
            return "\(item.stem).\(processedPart)"
        }

        return processedPart
    }
}

/// Records a rename operation for undo support.
public struct RenamePair: Sendable {
    public let source: URL
    public let destination: URL
}
