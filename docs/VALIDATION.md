# Validation record

## 0.2.0 Finder new-folder suggestions — 2026-10-22

This records evidence obtained during development, not an independent security certification. All new filesystem tests used isolated synthetic fixtures; no user document collection was renamed.

| Check | Observed result |
| --- | --- |
| Standalone Swift 6 safety regressions | 103 passed, 0 failed |
| Real FSEvents isolation tests | 7 passed, 0 failed; actual filesystem events in disposable fixture directories |
| Settings GUI | New-folder and shortcut pages opened; folder-assistance settings were usable; Command-comma opened the default new-folder page and shortcut entry points selected the shortcut page |
| Explicit root authorization | GUI directory selection and authorization completed |
| Restarted root access | The selected root's local security-scoped bookmark restored access after restarting the app |
| Finder GUI candidate and category selection | Actual Finder new-folder creation and committed input entered the passive suggestion queue; the explicit View menu opened/focused the card with all five complete names |
| Finder GUI adoption | Selecting `engineering` and clicking Adopt produced the expected complete name in Finder; the directory remained empty |
| Restarted History undo | After quit/relaunch, History confirmation restored the original name in Finder; the restored monitor bookmark avoided a repeated parent-directory prompt |
| Remove selected root | GUI removal cleared the root and changed monitoring to off; the temporary monitoring scope was stopped after verification |

The safety suite includes the existing naming, conflict, journal, recovery and undo cases, plus conservative category hints, direct-child empty-folder observations, and source/root identity checks for the new mode. A passing real-event harness is evidence about the exercised event cases; it does not establish that FSEvents can identify all human-created folders or distinguish every move, copy, extraction or coalesced event.

The complete GUI sequence used a disposable synthetic name, `uiprobe2`. Finder's actual Command-Shift-N created the empty folder; local input handling omitted an intended underscore, so the committed source name was verified as `uiprobe2`. The app menu's “查看当前文件夹建议…” explicitly focused the passive queued card for inspection. All five complete category names were readable; the unknown source showed the user's default `research`, without claiming a keyword recommendation. The tester selected `engineering`, adopted `2026_10_engineering_uiprobe2`, and verified that name and the empty directory in Finder. After quitting and reopening the app, the same local History record was confirmed for undo; Finder showed `uiprobe2` again. The root authorization was then removed and monitoring was verified off. The main README diagram uses the shorter fictional input `test` to illustrate this flow, rather than presenting a screenshot of that verification.

These GUI results apply to the current macOS 27.0.1 / Apple Silicon host. They do not establish behavior on every supported macOS version. macOS 14/15, a second physical Mac, actual on-device model output quality, real power loss, full disks and fsync fault injection remain outside the completed checks below.

## 0.1.0 baseline — 2026-10-21

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


## 0.1.1 shortcut settings — 2026-10-22

On the same macOS 27.0.1 host, the new main-window shortcut button and Command-comma opened the native Settings window. It displayed the recommended combination, service name and setup steps. Clicking the primary button opened the system Services keyboard-shortcut page directly; the service appeared under Files and Folders. The separate fallback button opened Keyboard settings. No shortcut binding or other system preference was changed during verification.

Debug and release builds passed, the release signature and absence of private build paths were checked, and the local installation was updated to 0.1.1 while retaining the old app as a backup. Cross-version page routing remains best-effort; successful URL dispatch is not reported as completed shortcut setup. The rename coordinator and its safety rules were unchanged.
