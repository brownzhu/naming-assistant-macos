import Foundation
import ImageIO

/// Extracts EXIF and XMP metadata from image files using CGImageSource.
public enum MetadataExtractor {

    /// Extracts metadata patterns from an image file.
    /// Returns a dictionary mapping pattern names to their string values.
    public static func extractPatterns(from url: URL, exif: Bool, xmp: Bool) -> [String: String] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return [:]
        }

        var patterns: [String: String] = [:]

        if exif {
            extractEXIF(from: source, into: &patterns)
        }

        if xmp {
            extractXMP(from: source, into: &patterns)
        }

        return patterns
    }

    // MARK: - EXIF Extraction

    private static func extractEXIF(from source: CGImageSource, into patterns: inout [String: String]) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return
        }

        // Top-level TIFF properties
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            setSanitized(&patterns, "CAMERA_MAKE", tiff[kCGImagePropertyTIFFMake as String] as? String)
            setSanitized(&patterns, "CAMERA_MODEL", tiff[kCGImagePropertyTIFFModel as String] as? String)
            setSanitized(&patterns, "AUTHOR", tiff[kCGImagePropertyTIFFArtist as String] as? String)
            setSanitized(&patterns, "COPYRIGHT", tiff[kCGImagePropertyTIFFCopyright as String] as? String)
            if let orientation = tiff[kCGImagePropertyTIFFOrientation as String] {
                patterns["ORIENTATION"] = "\(orientation)"
            }
        }

        // EXIF dictionary
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let first = iso.first {
                patterns["ISO"] = "\(first)"
            }
            if let fNumber = exif[kCGImagePropertyExifFNumber as String] as? Double {
                patterns["APERTURE"] = String(format: "f/%.1f", fNumber)
            }
            if let exposure = exif[kCGImagePropertyExifExposureTime as String] as? Double {
                if exposure < 1 {
                    patterns["SHUTTER"] = "1/\(Int(round(1.0 / exposure)))"
                } else {
                    patterns["SHUTTER"] = String(format: "%.1f", exposure)
                }
            }
            if let focal = exif[kCGImagePropertyExifFocalLength as String] as? Double {
                patterns["FOCAL"] = String(format: "%.0fmm", focal)
            }
            if let flash = exif[kCGImagePropertyExifFlash as String] as? Int {
                patterns["FLASH"] = (flash & 1) != 0 ? "On" : "Off"
            }
            if let bias = exif[kCGImagePropertyExifExposureBiasValue as String] as? Double {
                patterns["EXPOSURE_BIAS"] = String(format: "%+.1f", bias)
            }
            if let colorSpace = exif[kCGImagePropertyExifColorSpace as String] as? Int {
                patterns["COLOR_SPACE"] = colorSpace == 1 ? "sRGB" : "\(colorSpace)"
            }
            setSanitized(&patterns, "LENS", exif[kCGImagePropertyExifLensModel as String] as? String)

            // Date taken
            if let dateStr = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                parseDateComponents(dateStr, prefix: "DATE_TAKEN", into: &patterns)
            }
        }

        // Image dimensions
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Int {
            patterns["WIDTH"] = "\(width)"
        }
        if let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            patterns["HEIGHT"] = "\(height)"
        }

        // GPS
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String {
                let signed = latRef == "S" ? -lat : lat
                patterns["LATITUDE"] = String(format: "%.6f", signed)
            }
            if let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String {
                let signed = lonRef == "W" ? -lon : lon
                patterns["LONGITUDE"] = String(format: "%.6f", signed)
            }
            if let alt = gps[kCGImagePropertyGPSAltitude as String] as? Double {
                patterns["ALTITUDE"] = String(format: "%.1fm", alt)
            }
        }
    }

    // MARK: - XMP Extraction

    private static func extractXMP(from source: CGImageSource, into patterns: inout [String: String]) {
        // CGImageSource doesn't have a dedicated XMP dictionary, but many XMP fields
        // are mapped into standard property dictionaries. We also check for IPTC.
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return
        }

        // IPTC often contains XMP-equivalent fields
        if let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
            setSanitized(&patterns, "CREATOR", iptc[kCGImagePropertyIPTCCreatorContactInfo as String] as? String)
            setSanitized(&patterns, "RIGHTS", iptc[kCGImagePropertyIPTCRightsUsageTerms as String] as? String)
            setSanitized(&patterns, "TITLE", iptc[kCGImagePropertyIPTCObjectName as String] as? String)
            setSanitized(&patterns, "DESCRIPTION", iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String)
            if let keywords = iptc[kCGImagePropertyIPTCKeywords as String] as? [String] {
                setSanitized(&patterns, "SUBJECT", keywords.joined(separator: ", "))
            }
        }

        // TIFF for creator tool
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            setSanitized(&patterns, "CREATOR_TOOL", tiff[kCGImagePropertyTIFFSoftware as String] as? String)
            // Reuse author/copyright from TIFF if not already set
            if patterns["AUTHOR"] == nil {
                setSanitized(&patterns, "AUTHOR", tiff[kCGImagePropertyTIFFArtist as String] as? String)
            }
            if patterns["COPYRIGHT"] == nil {
                setSanitized(&patterns, "COPYRIGHT", tiff[kCGImagePropertyTIFFCopyright as String] as? String)
            }
        }

        // XMP create date from EXIF digitized date
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let dateStr = exif[kCGImagePropertyExifDateTimeDigitized as String] as? String {
                parseDateComponents(dateStr, prefix: "CREATE_DATE", into: &patterns)
            }
        }
    }

    // MARK: - Date Parsing

    /// Parses EXIF date string "YYYY:MM:DD HH:mm:SS" into individual pattern components.
    private static func parseDateComponents(
        _ dateString: String,
        prefix: String,
        into patterns: inout [String: String]
    ) {
        // EXIF date format: "2024:03:15 14:30:45"
        let parts = dateString.split(separator: " ")
        guard let datePart = parts.first else { return }

        let dateComponents = datePart.split(separator: ":")
        if dateComponents.count >= 3 {
            let year = String(dateComponents[0])
            let month = String(dateComponents[1])
            let day = String(dateComponents[2])

            patterns["\(prefix)_YYYY"] = year
            patterns["\(prefix)_YY"] = String(year.suffix(2))
            patterns["\(prefix)_MM"] = month
            patterns["\(prefix)_DD"] = day
        }

        if parts.count >= 2 {
            let timeComponents = parts[1].split(separator: ":")
            if timeComponents.count >= 3 {
                patterns["\(prefix)_HH"] = String(timeComponents[0])
                patterns["\(prefix)_mm"] = String(timeComponents[1])
                patterns["\(prefix)_SS"] = String(timeComponents[2])
            }
        }
    }

    // MARK: - Sanitization

    /// Sanitizes an attacker-controlled metadata string for safe inclusion in
    /// a filename. EXIF/IPTC/XMP fields can contain anything — including path
    /// separators (`/`, `:`), NUL bytes, or control characters — so we strip
    /// them here before they flow into a `$TOKEN` substitution and end up in
    /// the new filename. The validator catches these too, but doing it at
    /// extraction time means the rename succeeds with a clean value instead
    /// of failing at preview.
    static func sanitize(_ value: String) -> String? {
        let cleaned = value.unicodeScalars.filter { scalar in
            // Drop control chars (incl. NUL), and macOS-invalid filename chars.
            scalar.value >= 0x20
                && scalar.value != 0x7F
                && scalar != "/"
                && scalar != ":"
        }
        let result = String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject pure-dot or empty values — these are path-traversal components.
        if result.isEmpty || result.allSatisfy({ $0 == "." }) {
            return nil
        }
        return result
    }

    private static func setSanitized(
        _ patterns: inout [String: String],
        _ key: String,
        _ value: String?
    ) {
        guard let value, let cleaned = sanitize(value) else { return }
        patterns[key] = cleaned
    }
}
