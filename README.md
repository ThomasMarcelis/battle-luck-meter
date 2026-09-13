# xBro

A luck meter for Battle Brothers. During a battle a small bar sits under the round counter and shows whether
the dice have been running for you, against you, or evenly so far.

The bar runs from red on the left (unlucky), through neutral in the centre, to green on the right (lucky).
It has no changing percentage badges. The bar begins moving after the first counted attack, including a miss,
and is weighted by the evidence behind it: half way to the raw figure at attack 10, three quarters at attack 30,
always on the same side of the centre, so it moves less per attack while attacks are few. It fades in separately,
fully visible from attack 10. Hover for actual/expected hits, net hit swing and the raw rarity, such as **Bottom 5% of outcomes at these
odds** or **Top 5% of outcomes at these odds**. Rarity compares outcomes at the same hit chances and includes
ties; common outcomes read `Even`.

After victory, defeat or retreat, the Statistics tab shows **Battle luck** after the last brother, with the
rarity verdict and aligned hits-versus-expected totals for each side, without percentage badges. Its bar shows the
raw rarity at full emphasis, without the live bar's evidence weighting. The overview also shows net hit swing
and attack count. With a full party, scroll down through the cards to reach it. An empty battle says
`No attacks recorded` and shows `—` for both sides.

## Install

Requires [Modern Hooks](https://www.nexusmods.com/battlebrothers/mods/685) 0.6.0+ and
[MSU](https://www.nexusmods.com/battlebrothers/mods/479) 1.9.0+. Drop `mod_xbro-<version>.zip` into the game's
`data` folder. The visibility setting is in the MSU settings menu under xBro.

## What it measures

Each eligible hit-roll attack is one trial at its priced hit chance. Expected hits are the sum of those
probabilities per side. Expected hit totals on hover use two decimals. Net hit swing is your hits above
expectation minus theirs.

The bar uses the probability distribution of your hits plus enemy misses. Inclusive tails measure equally
unlucky or worse outcomes and equally lucky or better outcomes. If either tail is below 50%, its boundary
sets the raw rarity; otherwise the bar is neutral. The live bar weights that figure by the evidence behind
it, `50 + (raw rarity − 50) × n / (n + 10)` for n counted attacks, approaching it without ever reaching it.
Hover and the Statistics overview show the raw rarity, rounding group sizes up to a whole percent
(minimum 1%). There is no minimum-attack gate.

## Battle log

Every call through the hooked attack routine is journaled to `Documents/Battle Brothers/log.html`, including
excluded and disabled calls. Each attempt has an ID, round, actor/skill IDs and names, its exclusion reason or
all inputs used to price it, including whether the actors are allied. A separate result records the native return; nested attacks retain their own IDs.
Every counted result has a checkpoint with hits, expectations, variances, rarity, evidence weight, marker position and diagnostic hit deltas.
Settings changes, battle boundaries, errors, tooltip requests, battle/results UI pushes, rendered DOM values and teardown
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
or allied-faction sampling discrepancy, and `2` means incomplete evidence. Schema 2 journals remain supported; old v0.2 logs remain readable as arithmetic-only evidence.

Schema 3 entries begin `[xBro] schema=3 seq=... battle=... event=...`. Strings are quoted; unsafe bytes use
`%HH` escapes, decoded once after parsing. Probabilities use nine significant digits. Actor IDs identify
entities within the session; names are decoration. Squirrel and `[xBroUI]` browser receipts have separate
session sequences. Since 0.3.1, receipts go through MSU's session connection to Squirrel's logger,
preserving their originating battle and push IDs after tactical UI disconnection. Battle starts identify
the version, the probability, statistics, marker and UI models, and the receipt transport. Earlier console-based receipts
were absent from a live log; the new transport still needs live confirmation.

## What it deliberately does not measure

- Damage, injuries, morale checks, or anything other than hit or miss.
- Skills that do not make hit-roll attacks, forced hits, dead or unattackable targets, and
  unkillable targets at 1 hit point.
- Ranged shots with a blocked line of fire and diverted follow-up shots, because the chance shown is not the
  chance rolled.
- Fights that do not involve your company, and attacks between company members.
- Anything outside the current battle. The meter resets every fight; the journal retains the session.

## Limits

- The meter is a read-only instrument. It hooks the result of the engine's attack routine, consumes no random
  numbers, changes no mechanics, and never reads the combat log.
- The Lucky trait's reroll is priced in; every attack is otherwise priced at the chance the game displays.
- A rare engine path with an unclamped hit chance (a defence or skill at -100 or below) is priced at the
  displayed 5-95% range.
- Luck is measured against the odds the game showed you. It cannot tell you whether those odds were wise.
- Rarity uses the discrete distribution for the recorded hit chances, assuming independent trials. A verdict
  names an inclusive tail of that outcome distribution, not a rank among real battles: odds adapt and battles
  stop depending on outcomes.
- The current meter prices fractional chances directly and applies beginner difficulty to both Lucky hit
  checks. The auditor separately compares integer-die thresholds and an unshifted reroll, flags discrepancies,
  and exits `1`. This release preserves the existing attack-pricing model.
- Company-versus-allied-faction attacks currently count as opposing-side trials. The journal records
  alliance and the auditor flags these as model discrepancies.
- The hook cannot observe the native local roll/threshold, hidden modifiers, or attacks that bypass it.
  DOM receipts verify assigned values, not visual fit. More logging cannot establish those facts by itself.
- This release is an unverified prerelease. v0.2 logs were replayed from two live battles; the revised meter and diagnostic
  hooks still need an in-game player-loop and ZIP removal/reinstall check.
