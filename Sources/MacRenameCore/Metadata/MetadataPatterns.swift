import Foundation

/// Defines all supported metadata pattern names for EXIF and XMP tokens.
/// Matches PowerRename's MetadataTypes.h constants.
public enum MetadataPatterns {

    // MARK: - EXIF Patterns

    public static let exifPatterns: [String] = [
        // Camera
        "CAMERA_MAKE",
        "CAMERA_MODEL",
        "LENS",

        // Photo settings
        "ISO",
        "APERTURE",
        "SHUTTER",
        "FOCAL",
        "FLASH",
        "EXPOSURE_BIAS",

        // Image properties
        "WIDTH",
        "HEIGHT",
        "ORIENTATION",
        "COLOR_SPACE",

        // Location
        "LATITUDE",
        "LONGITUDE",
        "ALTITUDE",

        // Author
        "AUTHOR",
        "COPYRIGHT",

        // Date taken
        "DATE_TAKEN_YYYY",
        "DATE_TAKEN_YY",
        "DATE_TAKEN_MM",
        "DATE_TAKEN_DD",
        "DATE_TAKEN_HH",
        "DATE_TAKEN_mm",
        "DATE_TAKEN_SS",
    ]

    // MARK: - XMP Patterns

    public static let xmpPatterns: [String] = [
        // Author
        "CREATOR",
        "CREATOR_TOOL",
        "RIGHTS",

        // Document
        "TITLE",
        "DESCRIPTION",
        "SUBJECT",

        // IDs
        "DOCUMENT_ID",
        "INSTANCE_ID",
        "ORIGINAL_DOCUMENT_ID",
        "VERSION_ID",

        // Date
        "CREATE_DATE_YYYY",
        "CREATE_DATE_YY",
        "CREATE_DATE_MM",
        "CREATE_DATE_DD",
        "CREATE_DATE_HH",
        "CREATE_DATE_mm",
        "CREATE_DATE_SS",
    ]

    /// All pattern names combined (EXIF + XMP + shared).
    /// Some names like AUTHOR and COPYRIGHT appear in both EXIF and XMP.
    public static let allPatternNames: [String] = {
        var names = Set<String>()
        names.formUnion(exifPatterns)
        names.formUnion(xmpPatterns)
        return Array(names).sorted()
    }()

    /// File extensions that may contain EXIF metadata.
    public static let exifSupportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tif", "tiff", "heic", "heif", "avif", "dng", "cr2", "nef", "arw",
    ]

    /// Checks whether a file extension supports metadata extraction.
    public static func supportsMetadata(fileExtension ext: String) -> Bool {
        exifSupportedExtensions.contains(ext.lowercased())
    }
}
