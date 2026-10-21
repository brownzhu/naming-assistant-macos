# 0.1.0 validation record

Recorded on 2026-10-21. This is a development verification record, not an independent security certification.

| Check | Observed result |
| --- | --- |
| Standalone Swift 6 regressions | 75 passed, 0 failed |
| Preview | No rename before explicit confirmation |
| GUI rename / undo | Expected underscored name; original restored; contents unchanged |
| Restart undo | Private history recovered; exact parent reauthorized; original restored |
| Finder warm and cold service | Explicit synthetic selection received without loss |
| Glossary | Known Chinese yielded meeting_notes; unknown Chinese required manual English |
| Model unavailable | Actual unavailability shown with deterministic fallback; no inference performed |
| Build / signing | arm64 Mach-O, deployment target macOS 14.0, FoundationModels weak-linked; ad-hoc verification passed |
| Packaging | ZIP CRC and extracted app signature verified; public binary is checked for build/home paths after stripping debug records |

The interactive host ran macOS 27.0.1 / Apple Silicon / Swift 6.4. GUI was not tested on macOS 14/15 or a second physical Mac. Command-line CI results, when present, are separate evidence, not a substitute for those tests.

All rename tests used disposable synthetic fixtures. Originals were restored and a protected fixed-name sentinel remained unchanged. Crash cases simulated journal phases; real power loss, full disks and fsync fault injection were not tested. Actual on-device model output quality was not tested.

Regression coverage includes explicit/missing dates, timezone and extension rules, malformed/long names, no-confirm execution, preview-to-execute source changes, parent replacement, target races, case-fold/batch conflicts, links, Git/TeX/fixed names/common dependency folders, occupied undo originals, private journal permissions/schema/path validation, interrupted states, deferred/targeted recovery, large-file rejection and local glossary/model-disabled boundaries.

Known limitations remain in [SECURITY.md](../SECURITY.md) and [ROADMAP.md](../ROADMAP.md).
