import CryptoKit
import Darwin
import Foundation

struct SafeFileIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let owner: UInt32
    let mode: UInt16
    let links: UInt16
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(_ value: stat) {
        device = UInt64(bitPattern: Int64(value.st_dev))
        inode = UInt64(value.st_ino)
        owner = value.st_uid
        mode = value.st_mode
        links = value.st_nlink
        size = value.st_size
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
    }

    var isDirectory: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFDIR) }
    var isRegular: Bool { mode & UInt16(S_IFMT) == UInt16(S_IFREG) }
    func sameObject(as other: Self) -> Bool { device == other.device && inode == other.inode && owner == other.owner }
    func sameContentMetadata(as other: Self) -> Bool {
        sameObject(as: other) && mode == other.mode && links == other.links && size == other.size
            && modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
    }
}

struct SafeFileSnapshot: Codable, Sendable {
    let parentURL: URL
    let sourceName: String
    let destinationName: String
    let parentIdentity: SafeFileIdentity
    let identity: SafeFileIdentity
    let digest: String

    var sourceURL: URL { parentURL.appendingPathComponent(sourceName) }
    var destinationURL: URL { parentURL.appendingPathComponent(destinationName) }
}

enum SafeFS {
    static func fail(_ text: String) -> SafeRenameError { .rejected(text) }
    static func posix(_ operation: String) -> SafeRenameError {
        let code = errno
        return fail("\(operation): \(String(cString: strerror(code))) (\(code)).")
    }

    static func validBasename(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && name.utf8.count <= 255
            && !name.hasPrefix(".") && !name.hasSuffix(".") && !name.hasSuffix(" ")
            && name.rangeOfCharacter(from: .controlCharacters) == nil
            && !name.contains("/") && !name.contains(":") && !name.contains("\\")
    }

    static func validAbsoluteURL(_ url: URL) -> Bool {
        url.isFileURL && (url.host == nil || url.host == "" || url.host == "localhost")
            && url.path.hasPrefix("/") && url.path.utf8.count < 1024
            && url.path.rangeOfCharacter(from: .controlCharacters) == nil
            && !url.pathComponents.contains("..") && !url.pathComponents.contains(".")
    }

    /// Walk each component without following directory symlinks. Callers may
    /// explicitly canonicalize trusted system aliases before selection.
    static func openDirectory(_ url: URL, readingContents: Bool = true) throws -> Int32 {
        guard validAbsoluteURL(url) else { throw fail("Only absolute local file URLs are accepted.") }
        let parts = url.pathComponents.filter { $0 != "/" }
        var descriptor = Darwin.open("/", (parts.isEmpty && readingContents ? O_RDONLY | O_DIRECTORY : O_SEARCH) | O_CLOEXEC)
        guard descriptor >= 0 else { throw posix("Open root directory") }
        do {
            for (index, part) in parts.enumerated() {
                let access = readingContents && index == parts.count - 1 ? O_RDONLY | O_DIRECTORY : O_SEARCH
                let next = part.withCString { openat(descriptor, $0, access | O_NOFOLLOW | O_CLOEXEC) }
                guard next >= 0 else { throw posix("Open directory without following links") }
                close(descriptor)
                descriptor = next
            }
            return descriptor
        } catch { close(descriptor); throw error }
    }

    static func identity(fd: Int32) throws -> SafeFileIdentity {
        var value = stat()
        guard fstat(fd, &value) == 0 else { throw posix("Read file identity") }
        return SafeFileIdentity(value)
    }

    static func identity(at name: String, parentFD: Int32) throws -> SafeFileIdentity {
        var value = stat()
        let result = name.withCString { fstatat(parentFD, $0, &value, AT_SYMLINK_NOFOLLOW) }
        guard result == 0 else { throw posix("Read selected file identity") }
        return SafeFileIdentity(value)
    }

    static func names(in fd: Int32, maximumCount: Int? = nil) throws -> [String] {
        let copied = dup(fd)
        guard copied >= 0 else { throw posix("Duplicate directory handle") }
        guard let directory = fdopendir(copied) else { close(copied); throw posix("Read directory") }
        defer { closedir(directory) }
        rewinddir(directory)
        var result: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name != "." && name != ".." {
                result.append(name)
                if let maximumCount, result.count > maximumCount { throw fail("The directory exceeds the supported observation entry limit.") }
            }
            errno = 0
        }
        guard errno == 0 else { throw posix("Read directory entries") }
        return result
    }

    static func folded(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func ensureDestinationAbsent(_ name: String, parentFD: Int32) throws {
        guard !(try names(in: parentFD)).contains(where: { folded($0) == folded(name) }) else {
            throw fail("A case-insensitive destination collision exists.")
        }
    }

    static func fingerprint(name: String, parentFD: Int32) throws -> (SafeFileIdentity, String) {
        let initial = try identity(at: name, parentFD: parentFD)
        guard initial.owner == getuid(), initial.isRegular || initial.isDirectory else {
            throw fail("Only your ordinary files and empty folders are eligible; links and special files are protected.")
        }
        guard initial.isDirectory || initial.links == 1 else { throw fail("Files with multiple hard links are protected.") }
        let flags = O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (initial.isDirectory ? O_DIRECTORY : 0)
        let fd = name.withCString { openat(parentFD, $0, flags) }
        guard fd >= 0 else { throw posix("Open selected object") }
        defer { close(fd) }
        guard try identity(fd: fd) == initial else { throw fail("The selected object changed while being opened.") }
        let digest: String
        if initial.isDirectory {
            guard try names(in: fd).isEmpty else { throw fail("Non-empty folders are suggestion-only in this version; their contents are never traversed or renamed.") }
            digest = "empty_directory"
        } else {
            guard initial.size >= 0, initial.size <= 512 * 1024 * 1024 else {
                throw fail("Files larger than 512 MiB are suggestion-only in this version; no rename was attempted.")
            }
            var hasher = SHA256()
            var buffer = [UInt8](repeating: 0, count: 1024 * 1024)
            var bytesRead: Int64 = 0
            while true {
                if Task<Never, Never>.isCancelled { throw fail("The fingerprint check was cancelled.") }
                let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if count == 0 { break }
                if count < 0 {
                    if errno == EINTR { continue }
                    throw posix("Read content fingerprint")
                }
                bytesRead += Int64(count)
                guard bytesRead <= initial.size else { throw fail("The file grew while being checked; preview again after it is stable.") }
                hasher.update(data: Data(buffer.prefix(count)))
            }
            guard bytesRead == initial.size else { throw fail("The file changed size while being checked.") }
            digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        guard try identity(fd: fd) == initial, try identity(at: name, parentFD: parentFD) == initial else {
            throw fail("The selected object changed while its fingerprint was read.")
        }
        return (initial, digest)
    }

    static func checkedParent(_ snapshot: SafeFileSnapshot) throws -> Int32 {
        let fd = try openDirectory(snapshot.parentURL)
        do {
            let current = try identity(fd: fd)
            guard current.sameObject(as: snapshot.parentIdentity) else { throw fail("The parent folder was moved or replaced; preview again.") }
            guard current.mode & 0o022 == 0, current.owner == getuid() else {
                throw fail("The parent folder must belong to you and must not be writable by other users.")
            }
            return fd
        } catch { close(fd); throw error }
    }

    static func verifyParentPath(_ snapshot: SafeFileSnapshot, fd: Int32) throws {
        let current = try openDirectory(snapshot.parentURL)
        defer { close(current) }
        guard try identity(fd: current).sameObject(as: identity(fd: fd)) else {
            throw fail("The parent folder path changed during the operation.")
        }
    }

    static func verify(_ snapshot: SafeFileSnapshot, name: String, parentFD: Int32, exactMetadata: Bool) throws {
        let (current, digest) = try fingerprint(name: name, parentFD: parentFD)
        let metadataMatches = exactMetadata ? current == snapshot.identity : current.sameContentMetadata(as: snapshot.identity)
        guard metadataMatches, digest == snapshot.digest else { throw fail("The file identity or contents changed; automatic operation was refused.") }
    }

    static func renameExclusive(from: String, to: String, parentFD: Int32) throws {
        let status = from.withCString { source in
            to.withCString { destination in renameatx_np(parentFD, source, parentFD, destination, UInt32(RENAME_EXCL)) }
        }
        guard status == 0 else { throw posix("Rename without replacing an existing destination") }
        guard fsync(parentFD) == 0 else { throw posix("Synchronize parent directory") }
    }
}
