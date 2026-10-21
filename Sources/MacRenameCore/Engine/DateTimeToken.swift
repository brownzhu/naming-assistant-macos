import Foundation

/// Expands file timestamp patterns in a replace string.
/// Patterns: $YYYY, $YY, $Y, $MMMM, $MMM, $MM, $M, $DDDD, $DDD, $DD, $D,
///           $HH, $H, $hh, $h, $mm, $m, $ss, $s, $fff, $ff, $f, $TT, $tt
/// Matches PowerRename's GetDatedFileName behavior.
public enum DateTimeToken {

    /// Checks whether the replace string contains any date/time patterns.
    public static func containsTokens(in text: String) -> Bool {
        for pattern in orderedPatterns {
            if text.contains(pattern.token) {
                return true
            }
        }
        return false
    }

    /// Expands all date/time tokens in the replace string using the given date.
    public static func expand(_ text: String, date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents(
            [.year, .month, .day, .weekday, .hour, .minute, .second, .nanosecond],
            from: date
        )

        var result = text

        for pattern in orderedPatterns {
            guard result.contains(pattern.token) else { continue }
            let value = pattern.format(components, date)
            result = result.replacingOccurrences(of: pattern.token, with: value)
        }

        return result
    }

    // MARK: - Pattern Definitions

    private struct Pattern: Sendable {
        let token: String
        let format: @Sendable (DateComponents, Date) -> String
    }

    /// Patterns ordered longest-first to prevent partial matches
    /// (e.g., $YYYY must be matched before $YY before $Y).
    private static let orderedPatterns: [Pattern] = [
        // Year
        Pattern(token: "$YYYY") { c, _ in String(format: "%04d", c.year ?? 0) },
        Pattern(token: "$YY") { c, _ in String(format: "%02d", (c.year ?? 0) % 100) },
        Pattern(token: "$Y") { c, _ in String(c.year ?? 0) },

        // Month
        Pattern(token: "$MMMM") { _, d in
            let fmt = DateFormatter()
            fmt.dateFormat = "MMMM"
            return fmt.string(from: d)
        },
        Pattern(token: "$MMM") { _, d in
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM"
            return fmt.string(from: d)
        },
        Pattern(token: "$MM") { c, _ in String(format: "%02d", c.month ?? 0) },
        Pattern(token: "$M") { c, _ in String(c.month ?? 0) },

        // Day of week / Day of month
        Pattern(token: "$DDDD") { _, d in
            let fmt = DateFormatter()
            fmt.dateFormat = "EEEE"
            return fmt.string(from: d)
        },
        Pattern(token: "$DDD") { _, d in
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE"
            return fmt.string(from: d)
        },
        Pattern(token: "$DD") { c, _ in String(format: "%02d", c.day ?? 0) },
        Pattern(token: "$D") { c, _ in String(c.day ?? 0) },

        // Hour (24h)
        Pattern(token: "$HH") { c, _ in String(format: "%02d", c.hour ?? 0) },
        Pattern(token: "$H") { c, _ in String(c.hour ?? 0) },

        // Hour (12h)
        Pattern(token: "$hh") { c, _ in
            let h = (c.hour ?? 0) % 12
            return String(format: "%02d", h == 0 ? 12 : h)
        },
        Pattern(token: "$h") { c, _ in
            let h = (c.hour ?? 0) % 12
            return String(h == 0 ? 12 : h)
        },

        // AM/PM
        Pattern(token: "$TT") { c, _ in (c.hour ?? 0) < 12 ? "AM" : "PM" },
        Pattern(token: "$tt") { c, _ in (c.hour ?? 0) < 12 ? "am" : "pm" },

        // Minute
        Pattern(token: "$mm") { c, _ in String(format: "%02d", c.minute ?? 0) },
        Pattern(token: "$m") { c, _ in String(c.minute ?? 0) },

        // Second
        Pattern(token: "$ss") { c, _ in String(format: "%02d", c.second ?? 0) },
        Pattern(token: "$s") { c, _ in String(c.second ?? 0) },

        // Milliseconds
        Pattern(token: "$fff") { c, _ in
            let ms = (c.nanosecond ?? 0) / 1_000_000
            return String(format: "%03d", ms)
        },
        Pattern(token: "$ff") { c, _ in
            let ms = (c.nanosecond ?? 0) / 1_000_000
            return String(format: "%02d", ms / 10)
        },
        Pattern(token: "$f") { c, _ in
            let ms = (c.nanosecond ?? 0) / 1_000_000
            return String(ms / 100)
        },
    ]
}
