import Foundation

/// Which file timestamp to use for date/time token expansion.
public enum TimeSource: Sendable {
    case creation
    case modification
    case access
}
