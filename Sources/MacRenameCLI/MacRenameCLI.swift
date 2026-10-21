import ArgumentParser
import Foundation
import MacRenameCore

@main
struct MacRenameCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macrename",
        abstract: "Bulk file renaming tool for macOS",
        version: "0.1.0",
        subcommands: [Preview.self, Rename.self],
        defaultSubcommand: Preview.self
    )
}

struct CommonOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Search pattern")
    var search: String

    @Option(name: .shortAndLong, help: "Replacement string")
    var replace: String = ""

    @Flag(name: .long, help: "Use regular expressions")
    var regex: Bool = false

    @Flag(name: .long, help: "Case-sensitive matching")
    var caseSensitive: Bool = false

    @Flag(name: .shortAndLong, help: "Match all occurrences")
    var all: Bool = false

    @Flag(name: .long, help: "Rename only the filename stem")
    var nameOnly: Bool = false

    @Flag(name: .long, help: "Rename only the file extension")
    var extensionOnly: Bool = false

    @Flag(name: .long, help: "Convert to UPPERCASE")
    var uppercase: Bool = false

    @Flag(name: .long, help: "Convert to lowercase")
    var lowercase: Bool = false

    @Flag(name: .long, help: "Convert to Title Case")
    var titlecase: Bool = false

    @Flag(name: .long, help: "Convert to Capitalized")
    var capitalized: Bool = false

    @Flag(name: .long, help: "Enable ${start=,increment=,padding=} enumeration tokens")
    var enumerate: Bool = false

    @Flag(name: .long, help: "Enable ${rstringalnum=N}, ${ruuidv4} random tokens")
    var randomize: Bool = false

    @Flag(name: .long, help: "Use file creation time for $YYYY-style date tokens")
    var creationTime: Bool = false

    @Flag(name: .long, help: "Use file modification time for $YYYY-style date tokens")
    var modificationTime: Bool = false

    @Flag(name: .long, help: "Use file access time for $YYYY-style date tokens")
    var accessTime: Bool = false

    @Flag(name: .long, help: "Enable EXIF metadata tokens ($CAMERA_MAKE, $ISO, $DATE_TAKEN_*, etc.)")
    var exif: Bool = false

    @Flag(name: .long, help: "Enable XMP/IPTC metadata tokens ($CREATOR, $TITLE, $CREATE_DATE_*, etc.)")
    var xmp: Bool = false

    @Flag(name: .long, help: "Exclude files (only rename folders)")
    var excludeFiles: Bool = false

    @Flag(name: .long, help: "Exclude folders (only rename files)")
    var excludeFolders: Bool = false

    @Flag(name: .long, help: "Do not recurse into subdirectories")
    var noRecurse: Bool = false

    @Argument(help: "Files or directories to rename")
    var paths: [String]

    var flags: RenameFlags {
        var f: RenameFlags = []
        if caseSensitive { f.insert(.caseSensitive) }
        if all { f.insert(.matchAll) }
        if regex { f.insert(.useRegex) }
        if nameOnly { f.insert(.nameOnly) }
        if extensionOnly { f.insert(.extensionOnly) }
        if uppercase { f.insert(.uppercase) }
        if lowercase { f.insert(.lowercase) }
        if titlecase { f.insert(.titlecase) }
        if capitalized { f.insert(.capitalized) }
        if enumerate { f.insert(.enumerate) }
        if randomize { f.insert(.randomize) }
        if creationTime { f.insert(.creationTime) }
        if modificationTime { f.insert(.modificationTime) }
        if accessTime { f.insert(.accessTime) }
        if exif { f.insert(.metadataEXIF) }
        if xmp { f.insert(.metadataXMP) }
        if excludeFiles { f.insert(.excludeFiles) }
        if excludeFolders { f.insert(.excludeFolders) }
        if noRecurse { f.insert(.excludeSubfolders) }
        return f
    }

    var urls: [URL] {
        paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }
}

struct Preview: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Preview renames without executing them"
    )

    @OptionGroup var options: CommonOptions

    func run() async throws {
        let engine = RenameEngine()
        engine.searchTerm = options.search
        engine.replaceTerm = options.replace
        engine.flags = options.flags
        engine.addItems(urls: options.urls, recursive: !options.flags.contains(.excludeSubfolders))

        await engine.computePreview()

        for item in engine.items {
            switch item.status {
            case .shouldRename:
                print("\(item.originalName) → \(item.newName ?? "")")
            case .invalidCharacters:
                print("\(item.originalName) ✗ invalid characters in: \(item.newName ?? "")")
            case .filenameTooLong:
                print("\(item.originalName) ✗ filename too long: \(item.newName ?? "")")
            case .pathTooLong:
                print("\(item.originalName) ✗ path too long")
            case .excluded:
                break // silently skip
            case .unchanged, .initial, .nameAlreadyExists, .renamed:
                break
            }
        }

        let count = engine.items.filter { $0.status == .shouldRename }.count
        print("\n\(count) file(s) would be renamed.")
    }
}

struct Rename: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute renames"
    )

    @OptionGroup var options: CommonOptions

    func run() async throws {
        let engine = RenameEngine()
        engine.searchTerm = options.search
        engine.replaceTerm = options.replace
        engine.flags = options.flags
        engine.addItems(urls: options.urls, recursive: !options.flags.contains(.excludeSubfolders))

        await engine.computePreview()

        let pairs = try await engine.executeRename()
        for pair in pairs {
            print("\(pair.source.lastPathComponent) → \(pair.destination.lastPathComponent)")
        }
        print("\n\(pairs.count) file(s) renamed.")
    }
}
