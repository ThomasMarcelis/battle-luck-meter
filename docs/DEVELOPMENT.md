# Development

## Release acceptance

Tom confirmed Steam Deck testing and authorized publication of 1.0.2 on 2026-09-26. Record this as owner-reported runtime acceptance, not independent journal proof of each covered/diverted-shot or Lucky/Beginner edge case. Release preparation changes documentation only; runtime bytes remain those of the tested candidate.

Squirrel owns capture, validation, statistics, settings and tooltip content. JavaScript renders pushed state
and reports observed DOM values; receipts never update game or meter state.

| File | Responsibility |
| --- | --- |
| `scripts/!mods_preload/mod_battle_luck_meter.nut` | Registration, attack/battle/topbar/results hooks, delivery status |
| `scripts/mods/battle_luck_meter/core.nut` | Namespace, per-battle counters, session sequence, safe journal encoding |
| `scripts/mods/battle_luck_meter/capture.nut` | Eligibility/pricing inputs, pre-call attempts, linked results, calculation checkpoints |
| `scripts/mods/battle_luck_meter/stats.nut` | Incremental favorable-outcome distribution, rarity, mid-p sigma axis, evidence weighting and hit percentages |
| `scripts/mods/battle_luck_meter/ui.nut` | Settings history, tooltips, final result payload, correlated pushes |
| `ui/mods/battle_luck_meter/battle_luck_meter.js`, `battle_luck_meter.css` | Native bar and scrolling result summary, DOM receipts, stale push rejection, teardown |
| `tools/audit.py` | Strict journal replay and reference-pricing comparison; schema-2 arithmetic replay |

## Evidence contract

The native results `queryData` payload carries `battleLuckMeterLuck` only for a completed battle. The Statistics panel
appends the summary after its cards, using the same calculation and a concise form of the tooltip's side totals.
The verdict and the overview bar show the exact rarity at full emphasis, and enabled badges show the exact
unweighted percentages, without the live bar's sigma axis or evidence weighting: only the live surface is
smoothed. Aligned side summaries, net hit swing and sample context remain readable in the native scroll
area; content determines the card height. Hover uses a native header row for the verdict, then concise side
attack counts, expected hits, net swing and sample size.
Its content scrolls with the roster; list replacement and screen destruction dispose the view and tooltip.
An overflowing list uses native large-party card spacing to retain three columns beside the scrollbar.

Schema 3 uses a single session sequence and numbered battles. An `attempt` is written before the original
`attackEntity`; every returned call gets a `result`, even when excluded. Attempt IDs follow entry order;
results follow native return order, so nesting is valid. A counted result gets a full `state` checkpoint.
Exclusion records contain the inputs read up to that decision; there are no speculative property builds.
Since 1.0.2, an aimed ranged attack is priced at the original displayed chance even through cover. Its
recursive diverted `attackEntity` call carries `parent_attempt`, remains excluded as a separate sample,
and propagates any hit to the root shot; the root result logs both `native_hit` and the aggregated `hit`.
The `aimed_chance_any_hit_v1` model measures the player's selected risk, not the physical probability of
striking any actor. Older `displayed_chance_v1/v2` journals retain their prior blocked/diverted exclusions.
With Legends 19.4.22 installed, its legacy base-class callback rewrites `skill.attackEntity` for each
derived skill. The meter queues after Legends and registers a subsequent legacy base-class callback that
wraps the fresh ancestor method; without Legends it keeps the original Modern Hooks path. The Squirrel
regression checks repeated replacement and exact-once native calls. One 1.0.1 Legends battle recorded 51
attempts and 51 results, of which 44 counted and 7 were excluded. The auditor found no model discrepancies,
but cannot establish native hit odds; the screen-close event and removal/reinstall lifecycle remain open.

Battle-owned `mass` starts at `[1.0]` and convolves one Bernoulli trial per counted attack. Favorable means
an own hit or enemy miss. Summary reads normalize total mass and use inclusive tails, with a 1e-7 tolerance
at the median for float noise. Rarity group sizes round upward with a 0.0001 percentage-point tolerance at
integer boundaries. Updates cost O(n) time and battle state uses O(n) space; no attack list is kept in game.

The same read also takes the mid-p lower tail, mass strictly below the observed count plus half of the count's
own mass. The two sides sum to exactly one, so the bar's sign comes from a single number and a count sitting at
the median is exactly neutral, instead of the percentile axis's pinning at 50 followed by a jump of a whole
outcome. `::BattleLuckMeter.probit` converts that tail to standard deviations with a central rational approximation in
`r = q * q`, `q = p - 0.5`, evaluated by Horner. `Math.sqrt` and `Math.log` are not assumed to exist or to be
float-correct, so this needs only multiply, divide and add. `p` is clamped to `Phi(-+3)` first: that saturates
the axis at 2.9996 sigma instead of letting it diverge, and is the only bound the marker needs. Accuracy is
4.1e-4 sigma in double precision and 8.6e-4 sigma, 0.015 bar points, in float32; cancellation near the clip
also costs float32 evaluation up to 0.00125 sigma of monotonicity. The live marker is
`50 + (50 / 3) * z * n / (n + 10)`. A percentile axis is steepest at the centre, a sigma axis is evenly
sensitive. Order-dependent smoothing — slew caps, EMAs — is excluded: two identical tallies must render
identically, whatever order the attacks arrived in.

The internal state and journal retain each side's exact diagnostic delta, `100 * (hits / expected - 1)`,
rounded half away from zero without weighting or a positive cap, beside the live badge value, that delta times
the same side's own `n / (n + 10)`. `ui_model="smoothed_percent_option_v1"` renders the weighted figure live
and the exact figure on the results screen, only when `ShowPercentages` is enabled; it defaults off.
The hidden row has no reserved height, and a setting push toggles the existing live view in place. Hover/results
retain exact hit and expected-hit totals regardless of that option. The engine binds `Math.abs`, `Math.min` and `Math.max` to integer functions (start-line
probes `probe_abs=1 probe_min=74 probe_max=74`), so diagnostic percentages and swing magnitudes take their magnitude
through the float-preserving `::BattleLuckMeter.abs`, and `tests/fixtures.nut` emulates the integer bindings so a
native call cannot creep back in. Rounded zero and undefined
ratios have neutral diagnostic tones; enemy tones reverse the player mapping. Only the live surface is weighted by
evidence, `n / (n + 10)`; emphasis is a separate linear warm-up completing at counted attack 10.
The `MinAttacks` setting is removed. Results show the exact rarity at full emphasis.
The marker's horizontal position carries a 250 ms CSS transition on the tactical screen only. Receipts read the
inline style, which is the pushed target rather than an interpolated position, so the journal stays exact; the
results bar does not animate because it is a final figure.

Independent replay reconstructs expected hits and variance with float32 operations to match long-battle
accumulation, while rarity and the mid-p tail are checked against a double-precision distribution. The axis is
verified in three independent steps, reported in that order: the written `midp` against the replayed
distribution, the written `z` against `probit` of the written `midp`, and the written `marker` against the bar
geometry for the written `z`. Only the middle step carries a loose tolerance, 0.002 sigma or 0.03 bar points,
which is what the runtime's approximation is worth against the true quantile; everything else keeps the
existing tolerances, so an edit smaller than that still surfaces on the marker. A `start` line without
`marker_model` replays the 0.4.0/0.4.1 schema-3 semantics (linear warm-up, damped results, the earlier
verdict and sample wording); `marker_model="evidence_weight_v1"` is the 0.4.2-0.4.4 percentile axis and
`"probit_evidence_weight_v1"` the current sigma axis. The auditor derives `z` from the true inverse normal
rather than replaying the runtime's polynomial, so a mistyped coefficient is a finding instead of a
transcription shared by both sides. Percentages
are always checked against the float-correct model, so a 0.4.1 journal still fails on the truncation defect.
A checkpoint is recorded before it is judged, so a defective readout is one finding and the battle's end and
pushes are still traced instead of degrading into missing-end findings. Presentation is checked against the
validated runtime values to accommodate rounding ties. Legacy 0.4.1/0.4.2 schema 3 receipts report both
percentages and colour classes; 0.4.3 `bar_only_v1` receipts reject those fields and report only track opacity
and marker position; 0.4.4 `relative_percent_option_v1` journals keep the conditional badges but render the
exact figure live. The current UI contract reports `badges="hidden"` or `badges="rendered"`; only rendered
badges carry percentage and tone fields, weighted on the battle surface and exact on the results surface.
`tests/audit_test.py` rewrites the emitted journal of a one-attack battle into each earlier pre-release contract,
so every model keeps replaying under its own semantics rather than being grandfathered in.
Schema 2 retains its original replay path.

The current probability model is `aimed_chance_any_hit_v1`: it retains `displayed_chance_v2`'s pricing of
Beginner difficulty's first hit check and the Lucky target's unshifted fresh reroll, but judges each aimed shot
by whether any actor was hit. The auditor retains both earlier pricing models and separately compares the ordinary
integer-die reference. Discrepancies fail the audit instead of silently changing gameplay presentation. It
cannot inspect the native local threshold, future dice or unhooked/mod-replaced attack paths. Rarity assumes
independent reference trials at the original aimed odds, not the actual chance of hitting anyone; actual
battle length and later odds depend on outcomes.

Both battle and results surfaces publish correlated bar state. Results also report their rendered rarity, side totals, net swing and sample context,
including every replacement view when the native list reloads. A suppressed disabled result is acknowledged.
An ended, closed battle without a results payload is incomplete evidence.
`start` records version, all four model IDs, receipt transport, engine math probes and both settings; `settings` records changes; `end` records totals; `close` records native
screen exit, including abandoned battles. `push` identifies intended state. JS writes `[BattleLuckMeterUI]` observations
through MSU's existing session connection to Squirrel `logInfo`, with its own monotonic sequence. Native screen teardown disconnects the
screen's Squirrel handle before destroying DOM; MSU's connection remains available. Origin battle/push IDs
survive delayed receipts. The previous console transport produced no receipts in an earlier live battle; the 1.0.1 Legends
results screen did produce correlated receipts. Rendered exact result rows, inline marker position, opacity and display
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
results, broken logging/UI, malformed evidence, altered pricing/calculations/conditional DOM receipts, pre-release UI model contracts, Node behavior and
ES3 source syntax loading. The Python audit tests consume `tests/sample.nut` output from the real Squirrel
emitter. Diagnostic captures, source references, reports and generated packages stay in ignored paths.

One live Legends battle establishes in-game capture and results rendering, not accurate Legends odds,
complete native coverage or install/removal safety. The final screen-close receipt was absent;
package only as an unverified prerelease until the remaining lifecycle checks pass.
