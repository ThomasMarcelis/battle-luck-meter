// Decide whether skill.attackEntity is about to roll a priced die, and at what probability.
// Mirrors the exclusions in scripts/skills/skill.nut attackEntity; returns null when the call
// cannot be priced honestly from the engine's own getHitchance.
::XBro.classify <- function( _skill, _user, _target, _allowDiversion )
{
    if (_target == null || !_target.isAlive() || !_target.isAttackable()) return null;
    if (!_skill.isUsingHitchance()) return null;
    if (!_target.isAbleToDie() && _target.getHitpoints() == 1) return null;
    local player = ::Const.Faction.Player;
    local ours = _user.getFaction() == player, onUs = _target.getFaction() == player;
    if (ours == onUs) return null;
    if (_skill.isRanged())
    {
        // Diverted follow-up shot: rolled at toHit - 15, which getHitchance does not model.
        if (!_allowDiversion && _skill.m.IsShowingProjectile) return null;
        local userTile = _user.getTile(), targetTile = _target.getTile();
        // Blocked line of fire: the engine may retarget a blocking entity before rolling.
        if (_allowDiversion && userTile.getDistanceTo(targetTile) > 1
            && ::Const.Tactical.Common.getBlockedTiles(userTile, targetTile, _user.getFaction()).len() != 0) return null;
    }
    local chance = _skill.getHitchance(_target), shifted = chance;
    if (("Assets" in ::World) && ::World.Assets != null && ::World.Assets.getCombatDifficulty() == 0)
    {
        if (_user.isPlayerControlled()) shifted += 5;
        else if (_target.isPlayerControlled()) shifted -= 5;
    }
    local p = ::Math.minf(1.0, ::Math.maxf(0.0, shifted / 100.0));
    // Lucky trait: a hit is rerolled with RerollDefenseChance percent, and must hit again.
    local reroll = _target.getCurrentProperties().RerollDefenseChance / 100.0;
    if (reroll > 0.0) p = p - p * reroll * (1.0 - p);
    // chance and the names are for the log only; the meter uses side and p.
    return {side = ours ? "ours" : "theirs", p = p, chance = chance,
        skill = this.name(_skill), by = this.name(_user), on = this.name(_target)};
};

// A name is log decoration; failing to read one must not drop the attack from the meter.
::XBro.name <- function( _entity )
{
    try { return _entity.getName(); }
    catch (error) { return "?"; }
};

// Called before the native attack; never lets a failure reach it.
::XBro.price <- function( _skill, _user, _target, _allowDiversion )
{
    try { if (this.enabled()) return this.classify(_skill, _user, _target, _allowDiversion); }
    catch (error) { ::logError(this.Name + " capture failed: " + error); }
    return null;
};

// Called with the native attack's result. The log line is written after the push so that
// neither can suppress the other.
::XBro.settle <- function( _trial, _hit )
{
    local hit = _hit == true;
    try { this.record(_trial.side, _trial.p, hit); this.push(); }
    catch (error) { ::logError(this.Name + " update failed: " + error); }
    try
    {
        this.log("battle=" + this.Battle.id + " attack=" + (this.Battle.ours.n + this.Battle.theirs.n)
            + " side=" + _trial.side + " hit=" + (hit ? 1 : 0) + " chance=" + _trial.chance + ::format(" p=%.6f", _trial.p)
            + " skill=\"" + _trial.skill + "\" by=\"" + _trial.by + "\" on=\"" + _trial.on + "\"");
    }
    catch (error) { ::logError(this.Name + " log failed: " + error); }
};

// Called when the battle ends: the tooltip's numbers, written down next to the attack lines.
::XBro.finish <- function()
{
    local min = this.minAttacks(), s = this.summary(min);
    local side = @(_label, _side) " " + _label + "_n=" + _side.n + " " + _label + "_hits=" + _side.hits
        + ::format(" %s_expected=%.3f", _label, _side.expected);
    this.log("battle=" + this.Battle.id + " event=end" + side("ours", s.ours) + side("theirs", s.theirs)
        + ::format(" z=%.3f", s.z) + " rank=" + s.rank + " pending=" + (s.pending ? 1 : 0)
        + " min_attacks=" + min + " text=\"" + s.text + "\"");
};
