# Battle Luck Meter

A luck meter for Battle Brothers. During a battle a small bar sits under the round counter and shows whether
the dice have been running for you, against you, or evenly so far.

The bar runs from red on the left (unlucky), through neutral in the centre, to green on the right (lucky), and
is drawn on a standard-deviation scale: the centre is an average battle and each end is three standard
deviations away from it. One attack is worth roughly the same number of bar points wherever the marker happens
to sit, rather than far more near the middle than near the ends.

The bar begins moving after the first counted attack, including a miss, and is weighted by the evidence behind
it: half weight at attack 10, three quarters at attack 30, so it moves less per attack while attacks are few.
It fades in separately, fully visible from attack 10, and slides to each new position rather than jumping.

Relative hit-percentage badges are optional and off by default. When enabled, the live badges show each side's
hits against expected hits, scaled by how many attacks that side has made, so a single lucky early hit reads
`+17%` instead of `+186%`. The Statistics screen shows the exact figures.

Hover for actual/expected hits, net hit swing and the exact rarity, such as **Bottom 5% vs aimed odds** or
**Top 5% vs aimed odds**. Rarity compares outcomes against the original aimed hit chances and includes
ties; common outcomes read `Even`.

After victory, defeat or retreat, the Statistics tab shows **Battle luck** after the last brother, with the
rarity verdict and aligned hits-versus-expected totals for each side. The same optional percentage badges appear
there when enabled, showing the exact unweighted figures. Its bar shows the exact rarity at full emphasis,
without the live bar's standard-deviation axis or evidence weighting: only the in-battle display is smoothed.
The overview also shows net hit swing and attack count. With a full party, scroll down through the cards to reach it. An empty battle says
`No attacks recorded`; enabled percentage badges show `—` for both sides.

## Install

Requires [Modern Hooks](https://www.nexusmods.com/battlebrothers/mods/685) 0.6.0+ and
[MSU](https://www.nexusmods.com/battlebrothers/mods/479) 1.9.0+. Drop `mod_battle_luck_meter-<version>.zip` into the game's
`data` folder. The global visibility and relative-percentage settings are in the MSU settings menu under
**Battle Luck Meter**. Its technical mod ID and archive prefix are `mod_battle_luck_meter`; the identity introduced in 1.0.0 has no
install or settings aliases for the internal pre-release name.

Version 1.0.1 includes an experimental capture hook for Legends 19.4.22: it follows Legends' base-skill
replacement after inheritance, while vanilla continues to use Modern Hooks. In one live Legends battle,
the 1.0.1 runtime recorded 51 attempts, 7 exclusions and 44 counted attacks; the results screen showed
the same totals and its log audited with no model discrepancies. The screen-close event and the ZIP
removal/reinstall lifecycle were not observed. Legends may also change how hit chances are calculated;
accurate probabilities under Legends have not been established.

## What it measures

Each eligible shot is one trial at the original aimed target's displayed chance. Hitting that target or
someone else counts as one hit; hitting nobody counts as one miss. Cover and a diverted follow-up do not
erase or duplicate the shot. Expected hits sum those aimed chances per side; hover shows two decimals.
Net hit swing is your hits above that reference minus theirs. This is a score against the chances chosen,
not the physical probability of hitting anyone at all.

Both surfaces use the probability distribution of your hits plus enemy misses. Inclusive tails measure equally
unlucky or worse outcomes and equally lucky or better outcomes. If either tail is below 50%, its boundary sets
the exact rarity; otherwise the verdict is `Even`. Hover and the Statistics overview show that exact rarity,
rounding group sizes up to a whole percent (minimum 1%). There is no minimum-attack gate.

The live bar plots the same distribution on a standard-deviation axis. It takes the mid-p tail — everything
strictly below the observed favourable count, plus half of that count's own probability — and converts it to
standard deviations, clipped to ±3, which the track spans. That position is then weighted by evidence:
`50 + (50/3) × z × n / (n + 10)` for n counted attacks.

The live badges multiply each side's `100 × (hits / expected − 1)` by that side's own `n / (n + 10)`. The
exact figure is unbounded upward and floors at −100%, so early attacks alone could throw it across the width
of the readout.

## Battle log

Every call through the hooked attack routine is journaled to `Documents/Battle Brothers/log.html`, including
excluded and disabled calls. Each attempt has an ID, round, actor/skill IDs and names, its exclusion reason or
all inputs used to price it, including whether the actors are allied. A separate result records the native return
and the shot's final hit/miss; a diverted follow-up links to its parent and does not create another sample.
Every counted result has a checkpoint with hits, expectations, variances, the exact rarity, the mid-p tail and
its standard-deviation position, evidence weight, marker position, and both the weighted and the exact hit
percentages, so the smoothed display and the exact figure behind it are separately checkable.
Settings changes, battle boundaries, errors, tooltip requests, battle/results UI pushes, rendered DOM values, whether
percentage badges were hidden or rendered, and teardown
receipts are recorded too. Logging never reads or consumes dice.

Copy `log.html` before restarting the game: the engine overwrites it. Keep the **whole file**, including native
startup/version information and errors. In this repository run:

```
python3 tools/audit.py --attacks /path/to/log.html
```

The auditor derives eligibility and probability from the recorded inputs, replays every intermediate and final
calculation, and compares the rendered text/marker with the state sent by Squirrel. It rejects missing,
duplicate or inconsistent events and reports absent results, UI receipts and battle boundaries. Exit status
`0` means the journal checks passed within the stated limits, `1` means invalid evidence or a pricing-model
or allied-faction sampling discrepancy, and `2` means incomplete evidence. Schema 2 remains covered as an
arithmetic-only regression fixture; no pre-release identity aliases ship.

Schema 3 entries begin `[BattleLuckMeter] schema=3 seq=... battle=... event=...`. Strings are quoted; unsafe bytes use
`%HH` escapes, decoded once after parsing. Probabilities use nine significant digits. Actor IDs identify
entities within the session; names are decoration. Squirrel and `[BattleLuckMeterUI]` browser receipts have separate
session sequences. Since 0.3.1, receipts go through MSU's session connection to Squirrel's logger,
preserving their originating battle and push IDs after tactical UI disconnection. Battle starts identify
the version, the probability, statistics, marker and UI models, percentage setting, and receipt transport.
Synthetic fixtures retain the pre-release model semantics for regression coverage. Earlier console-based
receipts were absent from a live log; the current MSU transport produced correlated results receipts in
the Legends battle above. Screen-close evidence is still missing.

## What it deliberately does not measure

- Damage, injuries, morale checks, or anything other than hit or miss.
- Skills that do not make hit-roll attacks, forced hits, dead or unattackable targets, and
  unkillable targets at 1 hit point.
- Fights that do not involve your company, and attacks between company members.
- Anything outside the current battle. The meter resets every fight; the journal retains the session.

## Release status

Version 1.0.2: Tom confirmed Steam Deck testing and authorized publication on 2026-09-26. This is owner-reported runtime acceptance, not a claim that each rare capture or probability edge case has an independently retained live journal. Offline checks cover the shot-level capture and old-journal replay.

## Limits

- The meter is a read-only instrument. It hooks the result of the engine's attack routine, consumes no random
  numbers, changes no mechanics, and never reads the combat log.
- The Lucky trait's reroll is priced in; every attack is otherwise priced at the chance the game displays.
- A rare engine path with an unclamped hit chance (a defence or skill at -100 or below) is priced at the
  displayed 5-95% range.
- Luck is measured against the odds the game showed you. It cannot tell you whether those odds were wise.
- Rarity compares the shot results against the original aimed chances as independent reference trials. A
  redirected shot can hit someone at different actual odds, so this is **not** a calibrated probability of
  hitting anyone or a rank among real battles. Odds adapt and battles stop depending on outcomes.
- The live bar saturates at ±3 standard deviations: past that point only the evidence weight still moves the
  marker. The verdict, the rarity, the hover detail and the Statistics screen are exact and unaffected.
- The live bar reads the same distribution more finely than the verdict does, so the two can disagree by a
  little: a battle whose inclusive tails both exceed 50% reads `Even` while the bar sits slightly off centre.
  The verdict is the exact answer; the bar is the trend.
- The current meter prices fractional chances directly. On Beginner difficulty, the ±5 adjustment applies to
  the first hit check only; a Lucky target's fresh reroll uses the original displayed chance, matching the
  native attack routine's order. The auditor still flags fractional/integer-threshold discrepancies.
- Company-versus-allied-faction attacks currently count as opposing-side trials. The journal records
  alliance and the auditor flags these as model discrepancies.
- The hook cannot observe the native local roll/threshold, hidden modifiers, or attacks that bypass it.
  DOM receipts verify assigned values, not visual fit. More logging cannot establish those facts by itself.
- The Lucky/Beginner correction and 1.0.2 covered/diverted-shot edge cases have offline regression coverage. Tom has accepted the release after Steam Deck testing; no separately retained live journal isolates those particular edge cases or the ZIP removal/reinstall lifecycle.
