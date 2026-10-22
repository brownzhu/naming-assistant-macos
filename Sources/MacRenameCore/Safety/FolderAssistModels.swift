import Darwin
import Foundation

/// Session identity for a watched folder. Birth time distinguishes reused
/// inode numbers. This type is separate from the version-1 rename journals.
public struct FolderAssistIdentity: Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let owner: UInt32
    public let birthtimeSeconds: Int64
    public let birthtimeNanoseconds: Int64

    init(_ value: stat) {
        device = UInt64(bitPattern: Int64(value.st_dev))
        inode = UInt64(value.st_ino)
        owner = value.st_uid
        birthtimeSeconds = Int64(value.st_birthtimespec.tv_sec)
        birthtimeNanoseconds = Int64(value.st_birthtimespec.tv_nsec)
    }

    public var createdAt: Date? {
        guard birthtimeSeconds > 0, (0..<1_000_000_000).contains(birthtimeNanoseconds) else { return nil }
        return Date(timeIntervalSince1970: Double(birthtimeSeconds) + Double(birthtimeNanoseconds) / 1_000_000_000)
    }
}

public struct FolderAssistRoot: Sendable, Equatable {
    public let url: URL
    public let identity: FolderAssistIdentity
}

/// Metadata of one immediate child only. No child directory is expanded by a
/// baseline snapshot, and symbolic-link targets are not followed.
public struct FolderAssistEntry: Sendable, Equatable {
    public let name: String
    public let identity: FolderAssistIdentity
    public let isDirectory: Bool
    public var createdAt: Date? { identity.createdAt }
}

public struct FolderAssistObservation: Sendable, Equatable {
    public let root: FolderAssistRoot
    public let sourceURL: URL
    public let identity: FolderAssistIdentity
    public let createdAt: Date

    public func renameRequest(proposedName: String) -> SafeRenameRequest {
        SafeRenameRequest(sourceURL: sourceURL, proposedName: proposedName,
                          expectedSourceIdentity: identity, expectedParentIdentity: root.identity)
    }
}
