// Keep evidence at the same boundary as each decision. No extra property builds or
// dice are needed: these are the inputs the meter already reads, not live-actor dumps.
::XBro.classify <- function( _skill, _user, _target, _allowDiversion, _e = null )
{
    local e = _e == null ? {} : _e;
    e.target_present <- _target != null;
    e.reason <- "null_target";
    if (_target == null) return null;
    e.alive <- _target.isAlive(); e.reason = "dead_target";
    if (!e.alive) return null;
    e.attackable <- _target.isAttackable(); e.reason = "unattackable_target";
    if (!e.attackable) return null;
    e.uses_hitchance <- _skill.isUsingHitchance(); e.reason = "no_hitchance";
    if (!e.uses_hitchance) return null;
    e.able_to_die <- _target.isAbleToDie(); e.reason = "unkillable";
    if (!e.able_to_die)
    {
        e.hp <- _target.getHitpoints();
        if (e.hp == 1) return null;
    }
    e.player_faction <- ::Const.Faction.Player;
    e.by_faction <- _user.getFaction(); e.on_faction <- _target.getFaction();
    // Diagnostic only: preserve the current faction rule while exposing allied
    // cross-faction attacks. An observation failure must not change eligibility.
    try { e.allied <- _user.isAlliedWith(_target); }
    catch (error) { this.fail("alliance", error); }
    local ours = e.by_faction == e.player_faction, onUs = e.on_faction == e.player_faction;
    e.reason = "outside_sample";
    if (ours == onUs) return null;
    e.side <- ours ? "ours" : "theirs";
    e.ranged <- _skill.isRanged();
    if (e.ranged)
    {
        e.projectile <- _skill.m.IsShowingProjectile;
        e.reason = "diverted";
        if (!_allowDiversion && e.projectile) return null;
        local userTile = _user.getTile(), targetTile = _target.getTile();
        e.distance <- userTile.getDistanceTo(targetTile);
        if (_allowDiversion && e.distance > 1)
        {
            e.blockers <- ::Const.Tactical.Common.getBlockedTiles(userTile, targetTile, e.by_faction).len();
            e.reason = "blocked";
            if (e.blockers != 0) return null;
        }
    }
    e.chance <- _skill.getHitchance(_target);
    e.chance_type <- typeof e.chance;
    e.difficulty <- ("Assets" in ::World) && ::World.Assets != null ? ::World.Assets.getCombatDifficulty() : -1;
    e.shift <- 0;
    if (e.difficulty == 0)
    {
        e.by_controlled <- _user.isPlayerControlled();
        if (e.by_controlled) e.shift = 5;
        else
        {
            e.on_controlled <- _target.isPlayerControlled();
            if (e.on_controlled) e.shift = -5;
        }
    }
    e.shifted <- e.chance + e.shift;
    e.initial_p <- ::Math.minf(1.0, ::Math.maxf(0.0, e.shifted / 100.0));
    e.reroll <- _target.getCurrentProperties().RerollDefenseChance;
    local p = e.initial_p, reroll = e.reroll / 100.0;
    // Preserve the meter's current model. The offline audit also checks the source-
    // derived integer threshold and unshifted reroll, and reports any discrepancy.
    if (reroll > 0.0) p = p - p * reroll * (1.0 - p);
    e.p <- p; e.reason = "counted";
    return {side = e.side, p = p};
};

::XBro.identify <- function( _e, _prefix, _entity )
{
    if (_entity == null) return;
    try { _e[_prefix + "_id"] <- _entity.getID(); _e[_prefix] <- _entity.getName(); }
    catch (error) { this.fail("identity", error); }
};

// An attempt is written BEFORE the native call, including excluded calls. Its result
// follows afterwards and refers to the same ID even if native calls nest/re-enter.
::XBro.price <- function( _skill, _user, _target, _allowDiversion )
{
    this.Battle.attempts++;
    local trial = {battle = this.Battle, attempt = this.Battle.attempts, sample = null};
    local e = {attempt = trial.attempt, allow_diversion = _allowDiversion, reason = "capture_error"};
    this.identify(e, "skill", _skill); this.identify(e, "by", _user); this.identify(e, "on", _target);
    try { e.round <- ::Time.getRound(); }
    catch (error) { this.fail("round", error); }
    try
    {
        e.enabled <- this.enabled();
        if (this.Battle.ended) e.reason = "after_end";
        else if (!e.enabled) e.reason = "disabled";
        else trial.sample = this.classify(_skill, _user, _target, _allowDiversion, e);
    }
    catch (error) { e.reason = "capture_error"; this.fail("capture", error); }
    this.log("attempt", e);
    return trial;
};

::XBro.settle <- function( _trial, _hit )
{
    if (_trial == null) return;
    if (_trial.battle != this.Battle)
    {
        this.fail("settle", "stale battle=" + _trial.battle.id + " attempt=" + _trial.attempt);
        return;
    }
    this.Battle.results++;
    local counted = false;
    try
    {
        if (typeof _hit != "bool") this.fail("result", "native result is " + typeof _hit);
        if (this.Battle.ended) this.fail("settle", "result after battle end");
        else if (_trial.sample != null)
        {
            this.record(_trial.sample.side, _trial.sample.p, _hit == true);
            counted = true;
        }
        else this.Battle.excluded++;
    }
    catch (error) { this.fail("update", error); }
    this.log("result", {attempt = _trial.attempt, hit = _hit == true, result_type = typeof _hit,
        counted = counted, attack = this.Battle.ours.n + this.Battle.theirs.n});
    if (counted)
    {
        this.checkpoint("state");
        try { this.push(); }
        catch (error) { this.fail("push", error); }
    }
};

// Check every intermediate total, rarity, evidence weight and readout.
::XBro.checkpoint <- function( _event )
{
    local s = this.summary(), b = this.Battle;
    this.log(_event, {attempts = b.attempts, results = b.results, excluded = b.excluded, errors = b.errors,
        attack = s.n, ours_n = s.ours.n, ours_hits = s.ours.hits, ours_expected = s.ours.expected, ours_variance = b.ours.sumPQ,
        theirs_n = s.theirs.n, theirs_hits = s.theirs.hits, theirs_expected = s.theirs.expected, theirs_variance = b.theirs.sumPQ,
        rarity = s.rarity, weight = s.weight, marker = s.marker, emphasis = s.emphasis, swing = s.swing,
        ours_percent = s.ours.percent, ours_tone = s.ours.tone, theirs_percent = s.theirs.percent, theirs_tone = s.theirs.tone,
        enabled = this.enabled(), show_percentages = this.showPercentages(), text = s.text});
};

::XBro.finish <- function()
{
    if (this.Battle.ended) { this.fail("finish", "duplicate end"); return; }
    this.checkpoint("end");
    this.Battle.ended = true;
};
