import Foundation

public struct SafeRenameRequest: Sendable {
    public let sourceURL: URL
    public let proposedName: String
    public let expectedSourceIdentity: FolderAssistIdentity?
    public let expectedParentIdentity: FolderAssistIdentity?

    public init(sourceURL: URL, proposedName: String,
                expectedSourceIdentity: FolderAssistIdentity? = nil,
                expectedParentIdentity: FolderAssistIdentity? = nil) {
        self.sourceURL = sourceURL
        self.proposedName = proposedName
        self.expectedSourceIdentity = expectedSourceIdentity
        self.expectedParentIdentity = expectedParentIdentity
    }
}

public struct SafeRenamePlanEntry: Sendable {
    public let sourceURL: URL
    public let proposedName: String
    public let issues: [String]
    public var isReady: Bool { issues.isEmpty }
}

public struct SafeRenamePlan: Sendable {
    public let id: UUID
    public let entries: [SafeRenamePlanEntry]
    public var canExecute: Bool { !entries.isEmpty && entries.allSatisfy(\.isReady) }
}

public struct SafeRenameRecord: Sendable {
    public let sourceURL: URL
    public let destinationURL: URL
}

public struct SafeRenameReceipt: Sendable, Identifiable {
    public let id: UUID
    /// Renames still in effect. Empty after a completely successful undo.
    public let completed: [SafeRenameRecord]
    public let failures: [String]
    public let journalURL: URL
    /// Some attempted operations have an unverified outcome. Call history()
    /// before inferring success or attempting another undo.
    public let requiresRecovery: Bool
    /// UI must obtain user-selected-folder access before recovery or undo.
    public let recoveryParentURLs: [URL]
}

public enum SafeRenameError: LocalizedError, Sendable {
    case rejected(String)

    public var errorDescription: String? {
        switch self { case .rejected(let reason): return reason }
    }
}

/// Preserves recognized compound suffixes, including the original capitalization.
/// Unknown suffixes preserve the final extension; ambiguous names require review.
public enum SafeFilenameExtension {
    private static let compound = [
        ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.lz", ".tar.lzma",
        ".nii.gz", ".csv.gz", ".tsv.gz", ".json.gz", ".jsonl.gz", ".xml.gz",
        ".vcf.gz", ".bed.gz", ".fastq.gz", ".fq.gz", ".fasta.gz", ".fa.gz",
        ".d.ts", ".d.ts.map", ".js.map", ".css.map", ".user.js"
    ].sorted { $0.count > $1.count }

    public static func suffix(for filename: String) -> String {
        let lowered = filename.lowercased()
        for suffix in compound where lowered.hasSuffix(suffix) && filename.count > suffix.count {
            return String(filename.suffix(suffix.count))
        }
        guard let dot = filename.lastIndex(of: "."), dot != filename.startIndex else { return "" }
        return String(filename[dot...])
    }

    public static func stem(for filename: String) -> String {
        String(filename.dropLast(suffix(for: filename).count))
    }
}
