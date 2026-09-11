# xBro repository instructions

xBro is a small, solo-maintained native Battle Brothers mod. The product owner decides behavior and publication; the supervisor escalates real ambiguity; the implementing agent owns implementation judgment within the settled scope.

## Product boundary

- Target vanilla mechanics with all DLC. Modern Hooks and MSU are required; compatibility claims need evidence.
- Squirrel owns logic, validation, and persistence. JavaScript/CSS only present results and relay actions.
- Preserve the native UI. Read-only instrument: never mutate live actors, consume RNG, reveal future rolls, or change any game mechanic.
- Persist namespaced state only when the scope requires it. Preserve unknown future schemas unchanged.
- Distribute only work covered by this repository's MIT license. Do not redistribute game assets, decompiled source, dependencies, saves, or private captures.

## Layout and toolchain

- Runtime Squirrel lives under `scripts/mods/xbro/`; the preload is `scripts/!mods_preload/mod_xbro.nut`; presentation is under `ui/mods/xbro/`. Technical ID and ZIP prefix are `mod_xbro`.
- The preload includes `core.nut`, registers with `::Hooks.register(ID, Version, Name)`, calls `.require("mod_msu >= 1.9.0", "mod_modern_hooks >= 0.6.0")`, and does all other includes, MSU `Class.Mod` creation, settings registration, `::Hooks.registerLateJS`/`registerCSS`, and `.hook("scripts/...", function(q) { q.method = @(__original) function(...) { ... } })` inside `.queue(">mod_msu", ...)`. Wrap hook bodies in try/catch and `::logError` so a failure never breaks the native path.
- Settings go through `Mod.ModSettings.addPage(...)` with `addBooleanSetting` / `addRangeSetting`; read them with `getSetting(id).getValue()`.
- Game UI is Chromium 48 with jQuery. JavaScript is ES3 only: `var`, `function`, no arrow functions, `let`/`const`, template literals, or `Array.prototype.find`. Squirrel→JS is `JSHandle.asyncCall` with no return value; push state outward from Squirrel. Use native classes, fonts, and `coui://gfx/` assets; prefix all CSS classes and DOM ids with `xbro-`.
- The game runs Squirrel 3.0.4 with 32-bit integers and floats. Ignored `.tools/sq` (3.2) and `.tools/sq30` (3.0.7) are the local runners; both use 64-bit integers, so overflow is not caught locally. 3.2 accepts adjacent same-line `if` statements that 3.0.x rejects, and one compile error silently drops the entire chunk, so every suite must pass under `sq30` before packaging.
- `tools/check.py` runs the Squirrel suites (requiring a success marker and empty stderr), Node behavior tests, and `node --check` on all UI JavaScript. `tools/package.py` builds a deterministic `dist/mod_xbro-<version>.zip` from runtime files, README, LICENSE, notices, and docs only. The pinned `mod_msu-1.9.0.zip` in `.tools/` is hash-checked before its settings classes are extracted for the settings suite.
- Decompiled vanilla sources, the installed game under Steam, and the installed mod stack are read-only evidence. Cite file and line when an engine fact matters.

## Engineering

- Prefer one direct implementation per behavior. Do not add speculative abstractions, a second evaluator, a plugin framework, server, database, telemetry, or compatibility layer.
- Keep state and mutation at the owning boundary. Fix root causes. Add a dependency or layer only for a demonstrated need.
- State the invariant or scenario, write the smallest useful proof, implement, and verify. Keep tests focused on behavior: exclusions, arithmetic against hand-computed cases, lifecycle resets, settings, and stale callbacks.
- Avoid tests for static copy, CSS, or DOM structure. Do not retain historical suites as release gates when they duplicate stronger behavior checks.
- Substantial code changes require three independent final-diff reviews in parallel: correctness/architecture, simplicity/ownership, and changed-line value. Resolve material findings, subtract unnecessary work, and rerun proportionate checks. Documentation-only work does not require this ceremony.
- Keep maintained docs small. Store temporary status, plans, questions, evidence, tools, dependencies, saves, captures, and generated output only in ignored paths.

## UI

Use the game's visual language and controls. Keep text readable and structure obvious. Do not squeeze content to satisfy a viewport measurement. Source-derived geometry remains a hypothesis until rendered in game. Tear down every element the mod creates on screen destroy; do not leak DOM between battles or screens.

## Authorization

Research, repository-local edits and tooling, tests, packaging, and local commits are authorized. Other repositories, installed game files, and source snapshots are read-only evidence.

Runtime preparation may inspect the installed Steam edition and copy relevant saves for testing. Preserve originals byte-for-byte, prevent Cloud writeback, and keep private data out of Git and releases. Use the existing Steam client/session; do not create another installation or isolation framework. **The current owner restriction prohibits foreground game launch, input, or capture until explicitly lifted.** This restriction does not block independent code, tests, packaging, or read-only preparation.

Ask before creating or pushing a public repository, publishing a release, contacting suppliers or other people, making purchases, changing global/system configuration, changing the installed mod stack, or overwriting an original save. Stop at account or licensing barriers; never copy credentials.

Use ordinary reversible engineering judgment. Escalate product ambiguity, disputed strategy, scope changes, rights questions, or permission boundaries. If a decision is needed, record it briefly in ignored `questions.md` and continue independent work.

## Evidence and completion

Record exact commands, results, versions, and remaining gaps privately. Standalone Squirrel tests, source inspection, fixtures, and ZIP creation do not prove in-game fit, lifecycle safety, or platform compatibility.

A verified release requires the complete player loop and the ZIP removal/reinstall lifecycle on the declared baseline. Publish only as an unverified prerelease when runtime evidence is missing.
