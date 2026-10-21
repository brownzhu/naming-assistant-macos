import Foundation
import Darwin

/// Performs file rename operations with rollback support on failure.
public enum FileRenamer {

    /// Renames all items with `.shouldRename` status, deepest first.
    /// If any rename fails, previously completed renames are rolled back.
    ///
    /// - Parameter items: The rename items to process.
    /// - Returns: Array of completed rename pairs for undo support.
    /// - Throws: `RenameError` if an operation fails after rollback.
    public static func execute(items: [RenameItem]) throws -> [RenamePair] {
        let toRename = items
            .filter { $0.status == .shouldRename && $0.newName != nil }
            .sorted { $0.depth > $1.depth }

        var completed: [RenamePair] = []
        let fm = FileManager.default

        for item in toRename {
            guard let newName = item.newName else { continue }
            let sourceURL = item.url
            let destURL = sourceURL.deletingLastPathComponent().appendingPathComponent(newName)

            // On case-insensitive volumes (default APFS/HFS+), a rename that only
            // changes case reports "already exists" because the source and destination
            // resolve to the same inode. Detect this and do a two-step rename via a
            // temp name in the same directory.
            let isCaseOnlyRename = sourceURL.lastPathComponent != newName
                && sourceURL.lastPathComponent.lowercased() == newName.lowercased()

            do {
                if isCaseOnlyRename {
                    // Two-step temp-file dance — collision-free because of UUID.
                    let tempURL = sourceURL.deletingLastPathComponent()
                        .appendingPathComponent(".macrename-\(UUID().uuidString)")
                    try fm.moveItem(at: sourceURL, to: tempURL)
                    try fm.moveItem(at: tempURL, to: destURL)
                } else {
                    // Atomic rename: RENAME_EXCL fails with EEXIST if the
                    // destination exists, closing the TOCTOU window between a
                    // separate `fileExists` check and the move.
                    try atomicRename(from: sourceURL, to: destURL)
                }
                completed.append(RenamePair(source: sourceURL, destination: destURL))
            } catch let error as RenameError {
                throw failWithRollback(primary: error, completed: completed)
            } catch {
                let primary = RenameError.renameFailed(
                    source: sourceURL.lastPathComponent,
                    destination: newName,
                    underlying: error
                )
                throw failWithRollback(primary: primary, completed: completed)
            }
        }

        return completed
    }

    /// Performs an atomic rename via `renamex_np(2)` with `RENAME_EXCL`. If
    /// the destination already exists the kernel rejects the call with EEXIST
    /// rather than overwriting, so there is no race between an existence
    /// check and the move.
    private static func atomicRename(from source: URL, to dest: URL) throws {
        let result = source.path.withCString { src in
            dest.path.withCString { dst in
                renamex_np(src, dst, UInt32(RENAME_EXCL))
            }
        }
        if result == 0 { return }

        let err = errno
        let sourceName = source.lastPathComponent
        let destName = dest.lastPathComponent

        if err == EEXIST {
            throw RenameError.destinationExists(source: sourceName, destination: destName)
        }
        let underlying = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(err),
            userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(err))]
        )
        throw RenameError.renameFailed(source: sourceName, destination: destName, underlying: underlying)
    }

    /// Undoes a set of renames by moving files back to their original locations.
    /// Processes in reverse order (shallowest first, since execute went deepest first).
    public static func undo(_ pairs: [RenamePair]) throws {
        for pair in pairs.reversed() {
            try FileManager.default.moveItem(at: pair.destination, to: pair.source)
        }
    }

    /// Attempts to rollback completed renames, returning the pairs that
    /// could not be reversed (e.g. because the file was deleted or moved by
    /// another process between the rename and the rollback).
    private static func rollback(_ pairs: [RenamePair]) -> [RenamePair] {
        var unrecovered: [RenamePair] = []
        for pair in pairs.reversed() {
            do {
                try FileManager.default.moveItem(at: pair.destination, to: pair.source)
            } catch {
                unrecovered.append(pair)
            }
        }
        return unrecovered
    }

    /// Wraps the primary failure with rollback context: if the rollback was
    /// fully successful, returns the primary error; otherwise returns a
    /// `partialRollback` error that lists the pairs the caller must repair
    /// manually.
    private static func failWithRollback(
        primary: RenameError,
        completed: [RenamePair]
    ) -> RenameError {
        let unrecovered = rollback(completed)
        if unrecovered.isEmpty {
            return primary
        }
        return .partialRollback(primary: primary, unrecovered: unrecovered)
    }
}

/// Errors that can occur during rename operations.
public indirect enum RenameError: LocalizedError {
    case destinationExists(source: String, destination: String)
    case renameFailed(source: String, destination: String, underlying: Error)
    /// A rename failed AND the rollback couldn't fully undo earlier renames
    /// in the same batch. The unrecovered pairs need manual repair.
    case partialRollback(primary: RenameError, unrecovered: [RenamePair])

    public var errorDescription: String? {
        switch self {
        case .destinationExists(let source, let dest):
            return "Cannot rename '\(source)' to '\(dest)': a file with that name already exists."
        case .renameFailed(let source, let dest, let error):
            return "Failed to rename '\(source)' to '\(dest)': \(error.localizedDescription)"
        case .partialRollback(let primary, let unrecovered):
            let count = unrecovered.count
            let names = unrecovered.prefix(3)
                .map { "'\($0.destination.lastPathComponent)'" }
                .joined(separator: ", ")
            let suffix = unrecovered.count > 3 ? ", …" : ""
            return "\(primary.errorDescription ?? "Rename failed.") "
                + "Rollback could not be completed for \(count) file(s): \(names)\(suffix). "
                + "These files remain at their new names — please review."
        }
    }
}
