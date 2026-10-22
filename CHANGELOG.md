# Changelog

## 0.3.0 — 2026-10-22 — editable categories and glossary

- Added two local editors for category options and word conversions.
- Started with the existing five categories while allowing 1–20 total options, at least one visible option, editable labels/tokens/keywords, visibility, ordering and a visible default. Batch naming and Finder-folder cards share the configuration; the card scrolls when needed.
- Added a complete editable glossary of at most 100 `source = english_snake_case` entries. Built-in entries can be changed or deleted; a deleted conversion is not restored from an implicit fallback table. Unknown remaining text is not silently discarded.
- Prioritized valid explicit local dictionary conversions. Editing or applying these preferences does not automatically call a model or upload data; the optional on-device model remains a separate user action.
- Saved validated categories and the complete glossary in local `UserDefaults`; saving rules does not rename files or rewrite History. Existing preview, authorization, no-overwrite execution and state-checked undo remain in place.

Validation recorded 128 standalone safety checks and 8 real-event checks passing, plus Debug/Release build and signature checks. Isolated GUI verification covered edited categories/glossary surviving restart, a four-option card recommending the custom category, adoption and undo; see [the validation record](docs/VALIDATION.md) for scope and platform limitations. The illustrations showing five categories represent the initial configuration. The 0.2.0 GUI verification remains separate historical evidence.

## 0.2.0 — 2026-10-22 — Finder new-folder suggestions

- Added opt-in suggestions for newly created direct child empty folders in one selected root, with a locally saved security-scoped bookmark.
- Added a non-activating suggestion card after the committed name stabilizes, with five full category names, single selection, an editable English description and explicit adoption.
- Added conservative keyword category hints; neutral names such as `test`, unknown words and tied evidence remain a user choice.
- Used an explicit new-folder creation-month rule, separate from verified source dates for existing documents.
- Kept safe preview, identity/empty-folder/project/conflict checks, private History and state-checked undo before/after adoption.
- Excluded the baseline of existing children, placeholder names and uncertain events; root/permission changes or dropped events pause suggestions. The app must remain running, with menu-bar pause/settings/main-window entries; no login item is enabled automatically.

Filesystem events cannot prove that every candidate was manually created; copied, moved or coalesced activity can look similar. The feature is conservative and always requires confirmation. New-mode runtime verification and test results are recorded separately, not inferred from the earlier release's test count.

## 0.1.1 — 2026-10-22 — shortcut setup

- Added an app Settings entry (⌘,) and a visible “快捷键设置…” button in the main window.
- Displayed the recommended ⌃⌥⌘N combination, Finder service name and setup steps together.
- Added “打开系统快捷键设置” and fallback “打开键盘设置” buttons. System versions may open only the keyboard page; users still complete the final binding in System Settings.
- Kept the manual setup path and clarified that opening settings does not change system shortcuts automatically.

## 0.1.0 — 2026-10-21 — early preview

- Added date/category/English snake_case suggestions, explicit date confirmation and default file version v01.
- Added native AppKit interface, Finder service with cold-launch selection and configurable keyboard entry.
- Added local glossary and optional availability-checked Apple on-device filename descriptions.
- Added guarded no-overwrite execution, private persistent journals and state-checked undo/recovery.
- Added 75 standalone regression checks and an initial isolated GUI verification record.
- Published illustrated documentation and a staged improvement plan.

Known limits: empty independent folders and ordinary files up to 512 MiB only; incomplete custom-project/reference detection; unverified model output quality; ad-hoc signing without Apple notarization.
