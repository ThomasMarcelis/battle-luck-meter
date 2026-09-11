# xBro

A luck meter for Battle Brothers. During a battle a small bar sits under the round counter and shows whether
the dice have been running for you, against you, or evenly so far.

Marker left on green: lucky. Marker right on red: unlucky. `Lucky 93%` means 93% of battles with these odds
would have rolled worse for you; `Unlucky 93%` means 93% would have rolled better; `Even` means the dice are
within normal range. Hover the bar for the detail: hits versus expected hits for your attacks and for attacks
against you.

## Install

Requires [Modern Hooks](https://www.nexusmods.com/battlebrothers/mods/685) 0.6.0+ and
[MSU](https://www.nexusmods.com/battlebrothers/mods/479) 1.9.0+. Drop `mod_xbro-<version>.zip` into the game's
`data` folder. Settings (enable, minimum attacks before a verdict) are in the MSU settings menu under xBro.

## What it measures

Every attack the engine resolves with a hit roll is one trial at the chance the game itself displays. Your
attacks and attacks against you are kept as two samples. The meter compares hits above expectation on your
side with hits above expectation on theirs, scaled by the combined variance (a Poisson binomial z-score), and
reports where that lands among battles. It says nothing until enough attacks are in, and reads `Even` while the
difference is within half a standard deviation.

## What it deliberately does not measure

- Damage, injuries, morale checks, or anything other than hit or miss.
- Attacks that never roll: auto-hits such as Shieldwall and Spearwall, dead or unattackable targets, and
  unkillable targets at 1 hit point.
- Ranged shots with a blocked line of fire and diverted follow-up shots, because the chance shown is not the
  chance rolled.
- Attacks by or against anyone outside your company: war dogs, allied troops, fights between other factions,
  and friendly fire.
- Anything outside the current battle. The meter resets every fight.

## Limits

- The meter is a read-only instrument. It hooks the result of the engine's attack routine, consumes no random
  numbers, changes no mechanics, and never reads the combat log.
- The Lucky trait's reroll is priced in; every attack is otherwise priced at the chance the game displays.
- A rare engine path with an unclamped hit chance (a defence or skill at -100 or below) is priced at the
  displayed 5-95% range.
- Luck is measured against the odds the game showed you. It cannot tell you whether those odds were wise.
- This release is an unverified prerelease: it passes standalone tests and packaging checks but has not yet
  been exercised in a live game session.
