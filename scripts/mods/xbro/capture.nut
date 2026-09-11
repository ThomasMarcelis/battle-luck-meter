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
    local chance = _skill.getHitchance(_target);
    if (("Assets" in ::World) && ::World.Assets != null && ::World.Assets.getCombatDifficulty() == 0)
    {
        if (_user.isPlayerControlled()) chance += 5;
        else if (_target.isPlayerControlled()) chance -= 5;
    }
    local p = ::Math.minf(1.0, ::Math.maxf(0.0, chance / 100.0));
    // Lucky trait: a hit is rerolled with RerollDefenseChance percent, and must hit again.
    local reroll = _target.getCurrentProperties().RerollDefenseChance / 100.0;
    if (reroll > 0.0) p = p - p * reroll * (1.0 - p);
    return {side = ours ? "ours" : "theirs", p = p};
};

// Called before the native attack; never lets a failure reach it.
::XBro.price <- function( _skill, _user, _target, _allowDiversion )
{
    try { if (this.enabled()) return this.classify(_skill, _user, _target, _allowDiversion); }
    catch (error) { ::logError(this.Name + " capture failed: " + error); }
    return null;
};

// Called with the native attack's result.
::XBro.settle <- function( _trial, _hit )
{
    try { this.record(_trial.side, _trial.p, _hit == true); this.push(); }
    catch (error) { ::logError(this.Name + " update failed: " + error); }
};
