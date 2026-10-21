import Foundation

/// Validation status for a rename item after preview computation.
public enum RenameStatus: Sendable, Equatable {
    /// Initial state, not yet processed.
    case initial
    /// Item will be renamed.
    case shouldRename
    /// New name contains invalid characters.
    case invalidCharacters
    /// New filename exceeds 255 characters.
    case filenameTooLong
    /// New full path exceeds PATH_MAX (1024).
    case pathTooLong
    /// Another item already has this name in the same directory.
    case nameAlreadyExists
    /// Item is excluded by current flags.
    case excluded
    /// No change — new name equals original name.
    case unchanged
    /// The item was successfully renamed on disk.
    case renamed
}
