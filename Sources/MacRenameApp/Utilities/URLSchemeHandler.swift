import SwiftUI
import MacRenameCore

/// Handles the `macrename://` URL scheme for receiving files from the Finder extension.
struct URLSchemeHandler {

    /// Parses a `macrename://open?files=...` URL and returns file URLs.
    /// Only accepts `file://` entries — a malicious caller (e.g. a webpage
    /// invoking the URL scheme) cannot smuggle in `http://` or other schemes
    /// that would later resolve to unexpected destinations.
    static func parseURLScheme(_ url: URL) -> [URL]? {
        guard url.scheme == "macrename",
              url.host == "open" else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let filesParam = components.queryItems?.first(where: { $0.name == "files" })?.value else {
            return nil
        }

        let urls = filesParam
            .components(separatedBy: ",")
            .compactMap { URL(string: $0) }
            .filter { $0.isFileURL && $0.scheme == "file" }

        return urls.isEmpty ? nil : urls
    }
}
