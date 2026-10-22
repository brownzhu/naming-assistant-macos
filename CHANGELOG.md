# Changelog

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
