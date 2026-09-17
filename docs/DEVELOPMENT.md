# Development

Squirrel owns capture, validation, statistics, settings and tooltip content. JavaScript renders pushed state
and reports observed DOM values; receipts never update game or meter state.

| File | Responsibility |
| --- | --- |
| `scripts/!mods_preload/mod_xbro.nut` | Registration, attack/battle/topbar/results hooks, delivery status |
| `scripts/mods/xbro/core.nut` | Namespace, per-battle counters, session sequence, safe journal encoding |
| `scripts/mods/xbro/capture.nut` | Eligibility/pricing inputs, pre-call attempts, linked results, calculation checkpoints |
| `scripts/mods/xbro/stats.nut` | Incremental favorable-outcome distribution, rarity, evidence weighting and hit percentages |
| `scripts/mods/xbro/ui.nut` | Settings history, tooltips, final result payload, correlated pushes |
| `ui/mods/xbro/xbro.js`, `xbro.css` | Native bar and scrolling result summary, DOM receipts, stale push rejection, teardown |
| `tools/audit.py` | Strict journal replay and reference-pricing comparison; legacy arithmetic replay |

## Evidence contract

The native results `queryData` payload carries `xbroLuck` only for a completed battle. The Statistics panel
appends the summary after its cards, using the same calculation and a concise form of the tooltip's side totals.
The verdict and the overview bar show the raw rarity at full emphasis, without the live bar's evidence
weighting. Aligned side summaries, net hit swing and sample context remain readable in the native scroll
area; content determines the card height. Hover uses a native header row for the verdict, then concise side
attack counts, expected hits, net swing and sample size.
Its content scrolls with the roster; list replacement and screen destruction dispose the view and tooltip.
An overflowing list uses native large-party card spacing to retain three columns beside the scrollbar.

Schema 3 uses a single session sequence and numbered battles. An `attempt` is written before the original
`attackEntity`; every returned call gets a `result`, even when excluded. Attempt IDs follow entry order;
results follow native return order, so nesting is valid. A counted result gets a full `state` checkpoint.
Exclusion records contain the inputs read up to that decision; there are no speculative property builds.

Battle-owned `mass` starts at `[1.0]` and convolves one Bernoulli trial per counted attack. Favorable means
an own hit or enemy miss. Summary reads normalize total mass and use inclusive tails, with a 1e-7 tolerance
at the median for float noise. Rarity group sizes round upward with a 0.0001 percentage-point tolerance at
integer boundaries. Updates cost O(n) time and battle state uses O(n) space; no attack list is kept in game.

The internal state and journal retain each side's immediate diagnostic delta, `100 * (hits / expected - 1)`,
rounded half away from zero without weighting or a positive cap. `ui_model="relative_percent_option_v1"`
renders those volatile percentages on both surfaces only when `ShowPercentages` is enabled; it defaults off.
The hidden row has no reserved height, and a setting push toggles the existing live view in place. Hover/results
retain exact hit and expected-hit totals regardless of that option. The engine binds `Math.abs`, `Math.min` and `Math.max` to integer functions (start-line
probes `probe_abs=1 probe_min=74 probe_max=74`), so diagnostic percentages and swing magnitudes take their magnitude
through the float-preserving `::XBro.abs`, and `tests/fixtures.nut` emulates the integer bindings so a
native call cannot creep back in. Rounded zero and undefined
ratios have neutral diagnostic tones; enemy tones reverse the player mapping. Only the live bar is weighted by
evidence, `n / (n + 10)`; its emphasis is a separate linear warm-up completing at counted attack 10.
The `MinAttacks` setting is removed. Results show the raw rarity at full emphasis.

Independent replay reconstructs expected hits and variance with float32 operations to match long-battle
accumulation, while rarity is checked against a double-precision distribution. A `start` line without
`marker_model` replays the 0.4.0/0.4.1 schema-3 semantics (linear warm-up, damped results, the earlier
verdict and sample wording); `marker_model="evidence_weight_v1"` selects the current ones. Percentages
are always checked against the float-correct model, so a 0.4.1 journal still fails on the truncation defect.
A checkpoint is recorded before it is judged, so a defective readout is one finding and the battle's end and
pushes are still traced instead of degrading into missing-end findings. Presentation is checked against the
validated runtime values to accommodate rounding ties. Legacy 0.4.1/0.4.2 schema 3 receipts report both
percentages and colour classes; 0.4.3 `bar_only_v1` receipts reject those fields and report only track opacity
and marker position. The current UI contract reports `badges="hidden"` or `badges="rendered"`; only rendered
badges carry exact percentage and tone fields.
Schema 2 retains its original replay path.

The probability model remains `displayed_chance_v1`. The auditor verifies this calculation and separately
compares the ordinary integer-die reference (including the unshifted Lucky reroll). Discrepancies fail the
audit instead of silently changing gameplay presentation. It cannot inspect the native local threshold,
future dice or unhooked/mod-replaced attack paths. Rarity assumes independent trials at the recorded odds; actual battle length and later odds depend on outcomes.

Both battle and results surfaces publish correlated bar state. Results also report their rendered rarity, side totals, net swing and sample context,
including every replacement view when the native list reloads. A suppressed disabled result is acknowledged.
An ended, closed battle without a results payload is incomplete evidence.
`start` records version, all four model IDs, receipt transport, engine math probes and both settings; `settings` records changes; `end` records totals; `close` records native
screen exit, including abandoned battles. `push` identifies intended state. JS writes `[xBroUI]` observations
through MSU's existing session connection to Squirrel `logInfo`, with its own monotonic sequence. Native screen teardown disconnects the
screen's Squirrel handle before destroying DOM; MSU's connection remains available. Origin battle/push IDs
survive delayed receipts. The previous console transport produced no receipts in a live battle; confirm the
replacement in the next live journal. Rendered exact result rows, inline marker position, opacity and display
value and conditional badge content are checked offline; legacy percentage fields remain model-aware; receipts do not prove
visible geometry. Destruction of every rendered view is also reported. Views that never receive a push are not independently traced. Missing acknowledgements remain evidence gaps.

Squirrel diagnostic failures are structured and also reported through `logError`; a failed `logInfo` falls back
to an error at the same sequence. A wholly lost line leaves a gap. Unsafe string bytes are percent-escaped
inside quotes, including percent itself; decode once after parsing. Unknown schemas and duplicate keys fail.
UI errors are reported through the native console and recognized by the auditor. Native startup entries in the full log provide the game/DLC/mod version context; do not trim them away.

## Checks and package

Ignored `.tools/` holds sq30 (3.0.7, release gate), sq (3.2), and pinned `mod_msu-1.9.0.zip` (hash in
THIRD_PARTY.md). Its actual settings/tooltip classes back the MSU suite.

```
python3 tools/check.py
python3 tools/package.py
```

Checks cover both Squirrel versions, settings/hooks, deterministic journal replay, exclusions, nested/stale
results, broken logging/UI, malformed evidence, altered pricing/calculations/conditional DOM receipts, legacy UI contracts, Node behavior and
ES3 source syntax loading. The Python audit tests consume `tests/sample.nut` output from the real Squirrel
emitter. Diagnostic captures, source references, reports and generated packages stay in ignored paths.

Standalone evidence cannot establish in-game fit, complete native coverage or install/removal safety. The new
journal/receipt path still needs live verification; package only as an unverified prerelease until then.
