import Foundation

/// Validates filenames and paths against macOS filesystem rules.
public enum FileValidator {

    /// Maximum length for a single filename component on HFS+/APFS.
    public static let maxFilenameLength = 255

    /// Maximum full path length on macOS (PATH_MAX).
    public static let maxPathLength = 1024

    /// Characters that are invalid in macOS filenames.
    /// `/` is the path separator, `:` is reserved (legacy HFS separator).
    public static let invalidCharacters: Set<Character> = ["/", ":"]

    /// Validates a proposed new filename and returns the appropriate status.
    public static func validate(
        newName: String,
        parentPath: String,
        isFolder: Bool
    ) -> RenameStatus {
        // Check for invalid characters
        if newName.contains(where: { invalidCharacters.contains($0) }) {
            return .invalidCharacters
        }

        // Reject NUL and other control characters — POSIX disallows NUL in
        // paths, and control chars produce filenames that misbehave in shells
        // and confuse downstream tools.
        if newName.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            return .invalidCharacters
        }

        // Reject path-traversal components. A regex replacement or metadata
        // token could produce ".." or ".", which when appended to the parent
        // URL would escape the intended directory.
        if newName == "." || newName == ".." {
            return .invalidCharacters
        }

        // Check for empty name
        if newName.isEmpty {
            return .invalidCharacters
        }

        // Check filename length (UTF-8 byte count for APFS)
        if newName.utf8.count > maxFilenameLength {
            return .filenameTooLong
        }

        // Check full path length
        let fullPath = (parentPath as NSString).appendingPathComponent(newName)
        if fullPath.utf8.count > maxPathLength {
            return .pathTooLong
        }

        return .shouldRename
    }

    /// Trims leading/trailing whitespace and trailing dots from a filename.
    /// Matches PowerRename's GetTrimmedFileName behavior.
    public static func trimFilename(_ name: String) -> String {
        var result = name

        // Trim leading whitespace
        while result.first?.isWhitespace == true {
            result.removeFirst()
        }

        // Trim trailing whitespace and dots
        while let last = result.last, last.isWhitespace || last == "." {
            result.removeLast()
        }

        return result
    }
}
