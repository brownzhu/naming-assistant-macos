> Historical upstream README at `3cdb3eb`. These instructions describe Quick Rename, not the current Naming Assistant app. Relative reference links point to that upstream baseline.

# Quick Rename

Bulk file renaming for macOS — a native port of Microsoft PowerToys' PowerRename.

Three ways to use it:

- **Standalone app** with drag-and-drop, live preview, and undo
- **`macrename` CLI** for scripts and one-liners
- **Right-click in Finder** via the Services menu

Pure Swift, SwiftUI, no third-party dependencies (besides
[swift-argument-parser](https://github.com/apple/swift-argument-parser) for the
CLI). Targets macOS 14 Sonoma and later; tested on macOS 26 Tahoe.

---

## Highlights

- **Search** literal or regex (`NSRegularExpression`, ICU flavour), case-sensitive optional
- **Scope** the whole filename, the stem only, or the extension only
- **Transforms** UPPERCASE / lowercase / Title Case / Capitalized
- **Tokens** in the replacement string:
  - `${start=1,padding=3}` — per-item counters
  - `${rstringalnum=8}`, `${ruuidv4}` — random strings
  - `$YYYY $MM $DD $HH $mm $ss` — file timestamp components
  - `$CAMERA_MAKE $ISO $DATE_TAKEN_YYYY` — EXIF/XMP image metadata
- **Atomic renames** with depth-first ordering, automatic rollback on failure
- **Duplicate detection** before any file is touched
- **Case-only renames** work on case-insensitive APFS/HFS+ via two-step rename
- **Undo** the last batch with ⌘Z
- **MRU history** for search/replace terms; settings persist across launches

---

## Install

### Standalone app + Finder integration

Requires Xcode and a free Apple ID for code signing.

```bash
brew install xcodegen          # one-time
./scripts/generate-xcodeproj.sh
open QuickRename.xcodeproj
# In Xcode: select QuickRename target → Signing & Capabilities →
# Team = <your Apple ID> (Personal Team). Repeat for FinderExtension.

./scripts/install-app.sh release user
```

That copies the signed `.app` to `~/Applications`, registers it with Launch
Services, and prompts you to enable the Service.

To get the right-click menu in Finder: System Settings → Keyboard → Keyboard
Shortcuts → Services → Files and Folders → enable **Rename with Quick Rename**.

### CLI only

```bash
swift build -c release
cp .build/release/macrename /usr/local/bin/   # optional
```

---

## Usage

Quick examples:

```bash
# Preview first, always
macrename preview -s 'IMG_' -r 'Photo_' ~/Pictures/*.jpg

# dd.mm.yy → yyyymmdd
macrename rename --regex -s '(\d{2})\.(\d{2})\.(\d{2})' \
                 -r '20$3$2$1' ~/Downloads/*.pdf

# Camera-style rename from EXIF
macrename rename --exif --regex --name-only -s '.+' \
  -r '$CAMERA_MAKE-$DATE_TAKEN_YYYY$DATE_TAKEN_MM$DATE_TAKEN_DD-ISO$ISO' \
  ~/Pictures/vacation/*.jpg
```

Full reference is in [USAGE.md](https://github.com/simcrauk/MacRename/blob/3cdb3eb/USAGE.md). The app also has an in-window help
under **Help ▸ Quick Rename Help** (⌘?) covering tokens, regex, shortcuts, and
recipes.

---

## Develop

Architecture, project layout, and the rename pipeline are documented in
[CLAUDE.md](https://github.com/simcrauk/MacRename/blob/3cdb3eb/CLAUDE.md). Roadmap and status in [PLAN.md](https://github.com/simcrauk/MacRename/blob/3cdb3eb/PLAN.md).

```bash
swift build              # core + CLI
swift test               # 76 unit tests
./scripts/test-cli.sh    # 23 CLI integration scenarios
./scripts/perf-test.sh   # benchmark on N files (default 10000)
```

The Xcode project is generated from [`project.yml`](https://github.com/simcrauk/MacRename/blob/3cdb3eb/project.yml) by XcodeGen
and is gitignored — edit `project.yml`, then rerun
[`scripts/generate-xcodeproj.sh`](https://github.com/simcrauk/MacRename/blob/3cdb3eb/scripts/generate-xcodeproj.sh).

---

## Status

| Surface | State |
|---------|-------|
| Engine (search, replace, tokens, transforms, validation) | Stable, full PowerRename parity |
| Standalone app | Stable; drag-and-drop, undo, MRU, persistence, accessibility labels |
| CLI | Stable; `preview` and `rename` subcommands |
| Right-click Finder integration | Working via Services on macOS 26 Tahoe (FIFinderSync extension is bundled too but Tahoe currently doesn't surface its menu) |

A FIFinderSync extension is bundled and signed; if a future macOS point release
restores its context-menu plumbing, it will activate automatically. Until then,
the Services-menu path is the reliable one.

---

## Credits

- **Designed by** Simon Craig
- **Code written by** Claude (Anthropic Claude Opus 4.6)
- Behavioural reference: Microsoft PowerToys' PowerRename
  (`src/modules/powerrename/lib/`)

## Licence

[MIT](https://github.com/simcrauk/MacRename/blob/3cdb3eb/LICENSE) — © 2026 Simon Craig.
