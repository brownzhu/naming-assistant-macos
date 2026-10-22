import Foundation

/// Stable category values used in portable, English filenames.
public enum NamingCategory: String, Codable, CaseIterable, Sendable {
    case life
    case research
    case engineering
    case learning
    case admin
}

public enum NamingItemKind: String, Codable, Sendable {
    case file
    case projectFolder
}

/// Explicit naming inputs. This model never reads filesystem timestamps.
public struct NamingRequest: Codable, Equatable, Sendable {
    /// The caller must choose a date supported by the document or user input.
    /// A missing date produces `undated`; it is never replaced by today's date.
    public var date: Date?
    public var category: NamingCategory
    public var description: String
    public var kind: NamingItemKind
    public var version: Int?

    /// Complete extension, with or without its leading dot, e.g. `PDF` or
    /// `.nii.gz`. Case and all internal dots are preserved without alteration.
    public var fileExtension: String

    public init(
        date: Date? = nil,
        category: NamingCategory,
        description: String,
        kind: NamingItemKind = .file,
        version: Int? = nil,
        fileExtension: String = ""
    ) {
        self.date = date
        self.category = category
        self.description = description
        self.kind = kind
        self.version = version
        self.fileExtension = fileExtension
    }
}

/// A pure naming template that only returns suggestions; it cannot rename files.
///
/// Files: `2026_10_20_research_cem_eit_proof_v01.PDF`
/// Project folders: `2026_10_research_cem_eit`
public struct NamingProfile: Codable, Equatable, Sendable {
    public var timeZoneIdentifier: String

    public init(timeZoneIdentifier: String = "Europe/Berlin") {
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// A conservative recognition guard, not evidence that a date is accurate.
    /// Already formatted names are left out of automatic suggestions by default.
    public static func matchesStandardStem(_ stem: String, kind: NamingItemKind, categoryTokens: [String] = []) -> Bool {
        let date = kind == .projectFolder ? "[0-9]{4}_[0-9]{2}" : "[0-9]{4}_[0-9]{2}_[0-9]{2}"
        // Additional tokens are validated as literals before entering this fixed
        // recognizer. User configuration is never treated as regex syntax.
        let tokens = Set(NamingCategory.allCases.map(\.rawValue) + categoryTokens.filter(NamingCategoryToken.isValid))
        let categories = tokens.sorted().map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = "^(?:" + date + "|undated)_(?:" + categories + ")_[a-z0-9]+(?:_[a-z0-9]+)*$"
        return stem.range(of: pattern, options: .regularExpression) != nil
    }

    public func suggestName(for request: NamingRequest) throws -> String {
        try suggestName(for: request, categoryToken: request.category.rawValue)
    }

    /// Uses an explicitly chosen, validated custom filename category while
    /// preserving the existing request/Codable API and all other naming rules.
    public func suggestName(for request: NamingRequest, categoryToken: String) throws -> String {
        guard NamingCategoryToken.isValid(categoryToken) else { throw NamingProfileError.invalidCategoryToken }
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw NamingProfileError.invalidTimeZone(timeZoneIdentifier)
        }

        let description = try Self.snakeCase(request.description)
        var fields = [try datePrefix(for: request, timeZone: timeZone), categoryToken, description]

        if let version = request.version {
            guard version > 0 else { throw NamingProfileError.invalidVersion }
            fields.append("v" + (version < 10 ? "0" : "") + String(version))
        }

        let suffix = try extensionSuffix(for: request)
        let name = fields.joined(separator: "_") + suffix
        guard name.utf8.count <= 255 else { throw NamingProfileError.filenameTooLong }
        return name
    }

    /// Normalizes existing English words; does not translate or invent content.
    /// ASCII punctuation and whitespace become one underscore. Non-ASCII input
    /// is rejected so a Chinese description cannot silently lose its meaning.
    public static func snakeCase(_ description: String) throws -> String {
        guard description.unicodeScalars.allSatisfy(\.isASCII) else {
            throw NamingProfileError.descriptionRequiresEnglish
        }

        // Preserve word boundaries when callers supply camelCase or XMLParser.
        let separated = description
            .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1_$2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        guard !separated.isEmpty else { throw NamingProfileError.emptyDescription }
        return separated
    }

    private func datePrefix(for request: NamingRequest, timeZone: TimeZone) throws -> String {
        guard let date = request.date else { return "undated" }
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw NamingProfileError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.era, .year], from: date)
        guard components.era == 1, let year = components.year, (1...9999).contains(year) else {
            throw NamingProfileError.invalidDate
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = request.kind == .projectFolder ? "yyyy_MM" : "yyyy_MM_dd"
        return formatter.string(from: date)
    }

    private func extensionSuffix(for request: NamingRequest) throws -> String {
        guard !request.fileExtension.isEmpty else { return "" }
        guard request.kind == .file else { throw NamingProfileError.folderHasExtension }

        let extensionText = request.fileExtension
        let suffixBody = extensionText.hasPrefix(".") ? String(extensionText.dropFirst()) : extensionText
        let forbidden = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters)
        guard extensionText.rangeOfCharacter(from: forbidden) == nil,
              extensionText == extensionText.trimmingCharacters(in: .whitespacesAndNewlines),
              !suffixBody.components(separatedBy: ".").contains(where: \.isEmpty),
              !extensionText.hasSuffix("."),
              extensionText.contains(where: { $0 != "." }) else {
            throw NamingProfileError.invalidExtension
        }
        return extensionText.hasPrefix(".") ? extensionText : "." + extensionText
    }
}

public enum NamingProfileError: Error, Equatable, Sendable, LocalizedError {
    case invalidTimeZone(String)
    case invalidDate
    case emptyDescription
    case descriptionRequiresEnglish
    case invalidVersion
    case folderHasExtension
    case invalidExtension
    case filenameTooLong
    case invalidCategoryToken

    public var errorDescription: String? {
        switch self {
        case .invalidTimeZone(let identifier):
            return "Unknown time zone: \(identifier)."
        case .invalidDate:
            return "The supplied date must be finite and within Gregorian years 0001–9999."
        case .emptyDescription:
            return "Enter a description containing English letters or digits."
        case .descriptionRequiresEnglish:
            return "Enter an English description; automatic translation is not enabled."
        case .invalidVersion:
            return "The version must be a positive integer."
        case .folderHasExtension:
            return "A project folder cannot have a file extension."
        case .invalidExtension:
            return "The supplied extension contains an invalid filename character or trailing dot."
        case .filenameTooLong:
            return "The suggested filename exceeds 255 bytes."
        case .invalidCategoryToken:
            return "The category token must be at most 24 bytes of lowercase ASCII snake_case, beginning with a letter."
        }
    }
}
