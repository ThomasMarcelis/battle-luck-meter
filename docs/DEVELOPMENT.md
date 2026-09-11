# Development

Squirrel owns capture, statistics, settings, and the tooltip; JavaScript only renders what Squirrel pushes.

| File | Responsibility |
| --- | --- |
| `scripts/!mods_preload/mod_xbro.nut` | Registration, requirements, the three hooks |
| `scripts/mods/xbro/core.nut` | Namespace, version, per-battle accumulators, battle numbering, log line prefix |
| `scripts/mods/xbro/stats.nut` | Poisson binomial summary, normal CDF, bounded offset, readout |
| `scripts/mods/xbro/capture.nut` | Which `attackEntity` calls count and at what probability; attack and end-of-battle log lines |
| `scripts/mods/xbro/ui.nut` | Settings, dynamic tooltip, state pushed to JS |
| `ui/mods/xbro/xbro.js`, `xbro.css` | Bar under the round counter; create, update, destroy |
| `tools/audit.py` | Rebuilds each battle in a `log.html` from its `[xBro]` attack lines and checks the end line |

Capture prices each trial with the engine's own `getHitchance` before the native attack runs and records the
boolean result after; exclusions mirror `scripts/skills/skill.nut` `attackEntity` and are listed in README.
Push goes through a method added to the topbar round-information module, so JS never pulls and the element is
torn down with the native module. The audit log goes through the engine's `logInfo`, a mod's only persistent
output; `tactical_state.onInit` opens a numbered battle and `onBattleEnded` writes its summary. Entries are
single-line `key=value` text with no HTML, because `log.html` renders markup.

## Checks and package

Ignored `.tools/` holds `sq30` (Squirrel 3.0.7, the release gate), `sq` (3.2), and the pinned
`mod_msu-1.9.0.zip` (hash in THIRD_PARTY.md) whose classes back `tests/settings.nut`.

```
python3 tools/check.py     # forbidden-reference guard, both Squirrel runners, log audit round trip, Node tests, node --check
python3 tools/package.py   # dist/mod_xbro-<version>.zip, deterministic, prints SHA256
```

## Acceptance boundary

Standalone tests prove the arithmetic, the exclusions, lifecycle resets, settings, JS rendering, and that
`tools/audit.py` rebuilds the mod's own log lines (`tests/sample.nut` emits a scripted session). They do not
prove in-game fit under the topbar plaque, tooltip rendering, Chromium 48 loading, or the install and removal
lifecycle. Until a live session confirms those, releases are unverified prereleases.
