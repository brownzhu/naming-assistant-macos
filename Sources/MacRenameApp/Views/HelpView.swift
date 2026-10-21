import SwiftUI

/// The Help window shown from Help ▸ Quick Rename Help or ⌘?.
struct HelpView: View {
    @State private var selection: HelpSection = .gettingStarted

    var body: some View {
        HSplitView {
            List(HelpSection.allCases, id: \.self, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(selection.title)
                        .font(.title)
                        .bold()
                    selection.body
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 500)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

enum HelpSection: String, CaseIterable, Identifiable {
    case gettingStarted, searchModes, tokens, regex, shortcuts, tips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting started"
        case .searchModes:    "Search & scope"
        case .tokens:         "Tokens"
        case .regex:          "Regex cheat sheet"
        case .shortcuts:      "Keyboard shortcuts"
        case .tips:           "Tips & recipes"
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "bolt.horizontal"
        case .searchModes:    "magnifyingglass"
        case .tokens:         "curlybraces"
        case .regex:          "textformat.abc.dottedunderline"
        case .shortcuts:      "command"
        case .tips:           "lightbulb"
        }
    }

    @ViewBuilder
    var body: some View {
        switch self {
        case .gettingStarted: GettingStartedSection()
        case .searchModes:    SearchModesSection()
        case .tokens:         TokensSection()
        case .regex:          RegexSection()
        case .shortcuts:      ShortcutsSection()
        case .tips:           TipsSection()
        }
    }
}

// MARK: - Sections

private struct GettingStartedSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpText("1. Drag files or folders into the window, or click **Choose Files…**")
            HelpText("2. Type in **Search for…** and **Replace with…**. The preview updates after ~150ms.")
            HelpText("3. Rows that will change show a blue **Rename** badge. Problems (invalid characters, too long, collisions) show red or orange.")
            HelpText("4. Uncheck any row you want to skip.")
            HelpText("5. Click **Rename N File(s)** and confirm. Renamed rows flip to a green **Renamed** badge.")
            HelpText("6. **⌘Z** undoes the last batch.")
            Divider().padding(.vertical, 4)
            HelpText("Your last search/replace terms persist across launches. The clock menu next to each text field offers recent entries.")
        }
    }
}

private struct SearchModesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpSubsection("Search modes")
            HelpRow("Aa", "Case sensitive — distinguishes upper/lower case.")
            HelpRow(".*", "Regex — full NSRegularExpression (ICU, close to ECMAScript).")
            HelpRow("All", "Match all occurrences, not just the first.")
            HelpText("NFC normalization and non-breaking-space folding are applied automatically, so copy-pasted search terms don't silently miss.")

            HelpSubsection("Apply to")
            HelpText("**Full name** — search the whole filename including the extension (default).")
            HelpText("**Name only** — preserve the extension; search/replace runs on the stem only.")
            HelpText("**Extension only** — preserve the stem; search/replace runs on the extension.")

            HelpSubsection("Filters")
            HelpText("**Exclude files** / **Exclude folders** — restrict to one kind. **Exclude subfolders** — don't recurse into dropped folders.")
        }
    }
}

private struct TokensSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HelpText("Tokens expand inside the **Replace** field. Each category has an Options toggle that must be on. Use the `{…}` menu next to Replace to insert them.")

            HelpSubsection("Enumeration — Enumerate toggle")
            HelpRow("${start=1,increment=1,padding=3}", "Per-item counter with optional start, step, and zero-padding.")

            HelpSubsection("Random — Randomize toggle")
            HelpRow("${rstringalnum=N}", "N alphanumeric characters.")
            HelpRow("${rstringalpha=N}", "N letters.")
            HelpRow("${rstringdigit=N}", "N digits.")
            HelpRow("${ruuidv4}", "A UUID v4.")

            HelpSubsection("Date / time — pick a Time source (creation / modified / access)")
            HelpRow("$YYYY $YY $Y", "Year")
            HelpRow("$MMMM $MMM $MM $M", "Month (name or number)")
            HelpRow("$DDDD $DDD $DD $D", "Day of week or day of month")
            HelpRow("$HH $H / $hh $h", "Hour, 24-hour and 12-hour")
            HelpRow("$TT $tt", "AM/PM and am/pm")
            HelpRow("$mm $m / $ss $s", "Minute and second")
            HelpRow("$fff $ff $f", "Milliseconds")

            HelpSubsection("Image metadata — EXIF / XMP toggles")
            HelpText("Reads from the file via ImageIO. Works on jpg, jpeg, png, tif, heic, heif, dng, raw, etc.")
            HelpRow("$CAMERA_MAKE $CAMERA_MODEL $LENS", "Camera identification")
            HelpRow("$ISO $APERTURE $SHUTTER $FOCAL $FLASH", "Exposure")
            HelpRow("$WIDTH $HEIGHT $ORIENTATION", "Image dimensions")
            HelpRow("$LATITUDE $LONGITUDE $ALTITUDE", "GPS")
            HelpRow("$DATE_TAKEN_YYYY $DATE_TAKEN_MM $DATE_TAKEN_DD", "Capture date")
            HelpRow("$CREATOR $TITLE $DESCRIPTION $SUBJECT $RIGHTS", "IPTC / XMP")
            HelpText("Unknown tokens are left in place — useful for spotting typos.")
        }
    }
}

private struct RegexSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HelpRow(".", "Any character except newline")
            HelpRow(".*  /  .*?", "Any run, greedy / lazy")
            HelpRow("\\d \\D  /  \\w \\W  /  \\s \\S", "Digit, word character, whitespace — and their negations")
            HelpRow("^  $", "Start / end of the string")
            HelpRow("[abc]  /  [^abc]", "Character class / negated")
            HelpRow("(foo)  /  (?:foo)", "Capture / non-capture group")
            HelpRow("foo|bar", "Alternation")
            HelpRow("x{n}  x{n,}  x{n,m}", "Quantifiers")
            HelpRow("$1  $2  ...", "Backreferences inside Replace")
            Divider().padding(.vertical, 6)
            HelpText("Example — turn `dd.mm.yy` into `yyyymmdd`:")
            HelpRow("(\\d{2})\\.(\\d{2})\\.(\\d{2})", "Search")
            HelpRow("20$3$2$1", "Replace")
        }
    }
}

private struct ShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HelpSubsection("Open from Finder")
            HelpRow("⌃⌥⌘N", "Suggested Finder service shortcut; assign it once on each Mac.")
            HelpText("Open System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders. Enable **Rename with Quick Rename**, then assign **Control–Option–Command–N**, or another available combination.")
            HelpText("Select files in Finder and use this shortcut to open the preview. macOS can launch the installed app when needed. This service shortcut applies where selected files are available; it is not an always-on shortcut for every app. Opening the preview does not rename files.")
            Divider().padding(.vertical, 4)
            HelpSubsection("Inside the app")
            HelpRow("⌘O", "Open Files…")
            HelpRow("⌘A", "Select all rows")
            HelpRow("⇧⌘D", "Deselect all rows")
            HelpRow("⌘↩", "Rename (with confirmation)")
            HelpRow("⌘Z", "Undo last rename batch")
            HelpRow("⌘?", "Open this help window")
            HelpRow("⌘Q", "Quit")
        }
    }
}

private struct TipsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpSubsection("Always preview first")
            HelpText("The rename is atomic — either every item renames or none do — but a misjudged pattern can still produce surprising names. Read the preview carefully before you click Rename.")

            HelpSubsection("Stripping a prefix")
            HelpText("Turn on **Regex**, Search = `^IMG_`, Replace = (empty).")

            HelpSubsection("Sequencing screenshots")
            HelpText("Turn on **Regex** and **Enumerate**. Search = `.*`, Replace = `screenshot-${start=1,padding=3}`.")

            HelpSubsection("Camera-style photo rename")
            HelpText("Scope = **Name only**, **Regex** on, **EXIF** on. Search = `.+`, Replace = `$CAMERA_MAKE-$DATE_TAKEN_YYYY$DATE_TAKEN_MM$DATE_TAKEN_DD-ISO$ISO`.")

            HelpSubsection("Lowercasing every extension")
            HelpText("Scope = **Extension only**, Transform = **lowercase**, **Regex** on, Search = `.+`.")

            HelpSubsection("When things don't match")
            HelpText("Double-check the **Case sensitive** toggle and whether **Regex** is on. If you're using a token and it appears literally in the preview, the matching category toggle (Enumerate / Randomize / Time source / EXIF) is probably off.")
        }
    }
}

// MARK: - Primitives

private struct HelpText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(.init(text))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HelpSubsection: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.headline)
            .padding(.top, 6)
    }
}

private struct HelpRow: View {
    let code: String
    let text: String
    init(_ code: String, _ text: String) { self.code = code; self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .frame(minWidth: 180, alignment: .leading)
            Text(.init(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
