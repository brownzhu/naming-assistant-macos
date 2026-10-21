import Foundation

/// Option set matching PowerRename's PowerRenameFlags enum.
/// Controls search behavior, scoping, transformations, and token expansion.
public struct RenameFlags: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // Search behavior
    public static let caseSensitive       = RenameFlags(rawValue: 1 << 0)
    public static let matchAll            = RenameFlags(rawValue: 1 << 1)
    public static let useRegex            = RenameFlags(rawValue: 1 << 2)

    // Token expansion
    public static let enumerate           = RenameFlags(rawValue: 1 << 3)
    public static let randomize           = RenameFlags(rawValue: 1 << 13)

    // Scope filtering
    public static let excludeFiles        = RenameFlags(rawValue: 1 << 4)
    public static let excludeFolders      = RenameFlags(rawValue: 1 << 5)
    public static let excludeSubfolders   = RenameFlags(rawValue: 1 << 6)

    // Name part scoping
    public static let nameOnly            = RenameFlags(rawValue: 1 << 7)
    public static let extensionOnly       = RenameFlags(rawValue: 1 << 8)

    // Text transformations (mutually exclusive)
    public static let uppercase           = RenameFlags(rawValue: 1 << 9)
    public static let lowercase           = RenameFlags(rawValue: 1 << 10)
    public static let titlecase           = RenameFlags(rawValue: 1 << 11)
    public static let capitalized         = RenameFlags(rawValue: 1 << 12)

    // Time source (mutually exclusive)
    public static let creationTime        = RenameFlags(rawValue: 1 << 14)
    public static let modificationTime    = RenameFlags(rawValue: 1 << 15)
    public static let accessTime          = RenameFlags(rawValue: 1 << 16)

    // Metadata source
    public static let metadataEXIF        = RenameFlags(rawValue: 1 << 17)
    public static let metadataXMP         = RenameFlags(rawValue: 1 << 18)

    /// The active text transformation, if any.
    public var textTransform: TextTransform? {
        if contains(.uppercase) { return .uppercase }
        if contains(.lowercase) { return .lowercase }
        if contains(.titlecase) { return .titlecase }
        if contains(.capitalized) { return .capitalized }
        return nil
    }

    /// The active time source, if any.
    public var timeSource: TimeSource? {
        if contains(.creationTime) { return .creation }
        if contains(.modificationTime) { return .modification }
        if contains(.accessTime) { return .access }
        return nil
    }

    /// Whether any time-related flag is set.
    public var usesFileTime: Bool { timeSource != nil }

    /// Whether any metadata flag is set.
    public var usesMetadata: Bool {
        !intersection([.metadataEXIF, .metadataXMP]).isEmpty
    }
}
