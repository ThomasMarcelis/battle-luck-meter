# Development

Squirrel owns capture, statistics, settings, and the tooltip; JavaScript only renders what Squirrel pushes.

| File | Responsibility |
| --- | --- |
| `scripts/!mods_preload/mod_xbro.nut` | Registration, requirements, the three hooks |
| `scripts/mods/xbro/core.nut` | Namespace, version, per-battle accumulators |
| `scripts/mods/xbro/stats.nut` | Poisson binomial summary, normal CDF, bounded offset, readout |
| `scripts/mods/xbro/capture.nut` | Which `attackEntity` calls count and at what probability |
| `scripts/mods/xbro/ui.nut` | Settings, dynamic tooltip, state pushed to JS |
| `ui/mods/xbro/xbro.js`, `xbro.css` | Bar under the round counter; create, update, destroy |

Capture prices each trial with the engine's own `getHitchance` before the native attack runs and records the
boolean result after; exclusions mirror `scripts/skills/skill.nut` `attackEntity` and are listed in README.
Push goes through a method added to the topbar round-information module, so JS never pulls and the element is
torn down with the native module.

## Checks and package

Ignored `.tools/` holds `sq30` (Squirrel 3.0.7, the release gate), `sq` (3.2), and the pinned
`mod_msu-1.9.0.zip` (hash in THIRD_PARTY.md) whose classes back `tests/settings.nut`.

```
python3 tools/check.py     # forbidden-reference guard, both Squirrel runners, Node tests, node --check
python3 tools/package.py   # dist/mod_xbro-<version>.zip, deterministic, prints SHA256
```

## Acceptance boundary

Standalone tests prove the arithmetic, the exclusions, lifecycle resets, settings, and JS rendering. They do not
prove in-game fit under the topbar plaque, tooltip rendering, Chromium 48 loading, or the install and removal
lifecycle. Until a live session confirms those, releases are unverified prereleases.
