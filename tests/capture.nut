local X = ::XBro, cases = {};

function trial( _skill, _user, _target, _allowDiversion = true ) { return X.classify(_skill, _user, _target, _allowDiversion); }

cases.player_attack_and_enemy_attack_are_priced_by_side <- function()
{
    world();
    local ours = trial(skill(82), actor(1), actor(2));
    check(ours.side == "ours" && near(ours.p, 0.82, 1e-6), "our attack");
    local theirs = trial(skill(35), actor(2), actor(1));
    check(theirs.side == "theirs" && near(theirs.p, 0.35, 1e-6), "their attack");
};

cases.no_roll_early_returns_are_excluded <- function()
{
    world();
    local dead = actor(2); dead.alive = false;
    local wall = actor(2); wall.attackable = false;
    check(trial(skill(80), actor(1), null) == null, "null target");
    check(trial(skill(80), actor(1), dead) == null, "dead target");
    check(trial(skill(80), actor(1), wall) == null, "unattackable target");
};

cases.forced_outcomes_are_excluded <- function()
{
    world();
    local shieldwall = skill(100); shieldwall.hitchance = false;
    check(trial(shieldwall, actor(1), actor(2)) == null, "auto-hit skill");
    local unkillable = actor(2); unkillable.ableToDie = false; unkillable.hp = 1;
    check(trial(skill(80), actor(1), unkillable) == null, "unkillable at 1 hp");
    unkillable.hp = 2;
    check(trial(skill(80), actor(1), unkillable) != null, "unkillable above 1 hp still rolls");
};

cases.only_player_versus_other_factions_count <- function()
{
    world();
    check(trial(skill(80), actor(2), actor(3)) == null, "enemy on ally");
    check(trial(skill(80), actor(1), actor(1)) == null, "friendly fire");
    check(trial(skill(80), actor(3), actor(1)).side == "theirs", "any non-player faction attacking us");
};

cases.ranged_diversion_and_blocked_fire_are_excluded <- function()
{
    world();
    local bow = skill(60, true, true);
    check(trial(bow, actor(1, 4), actor(2), false) == null, "diverted follow-up shot");
    check(trial(bow, actor(1, 4), actor(2), true) != null, "clear line of fire");
    local handgonne = skill(60, true, false);
    check(trial(handgonne, actor(1, 4), actor(2), false) != null, "no projectile, no diversion penalty");
    world([{}]);
    check(trial(bow, actor(1, 4), actor(2), true) == null, "blocked line of fire");
    check(trial(bow, actor(1, 1), actor(2), true) != null, "adjacent shot never goes astray");
    check(trial(skill(60), actor(1, 4), actor(2), true) != null, "melee ignores blockers");
};

cases.beginner_difficulty_shifts_probability_like_the_engine <- function()
{
    world(null, 0);
    check(near(trial(skill(82), actor(1), actor(2)).p, 0.87, 1e-6), "player attacker +5");
    check(near(trial(skill(35), actor(2), actor(1)).p, 0.30, 1e-6), "player defender -5");
    check(near(trial(skill(95), actor(1), actor(2)).p, 1.0, 1e-6) && near(trial(skill(5), actor(2), actor(1)).p, 0.0, 1e-6), "clamped");
    world(null, 1);
    check(near(trial(skill(82), actor(1), actor(2)).p, 0.82, 1e-6), "other difficulties unchanged");
    delete ::World.Assets;
    check(near(trial(skill(82), actor(1), actor(2)).p, 0.82, 1e-6), "no assets, no shift");
};

cases.lucky_trait_reroll_lowers_the_priced_chance <- function()
{
    world();
    local lucky = actor(1); lucky.reroll = 10;
    check(near(trial(skill(50), actor(2), lucky).p, 0.475, 1e-6), "p - p * 0.1 * (1 - p)");
    check(near(trial(skill(100), actor(2), lucky).p, 1.0, 1e-6) && near(trial(skill(50), actor(2), actor(1)).p, 0.5, 1e-6), "no reroll, no change");
    world(null, 0);
    check(near(trial(skill(35), actor(2), lucky).p, 0.30 - 0.30 * 0.1 * 0.70, 1e-6), "reroll applies after the beginner shift");
};

cases.price_then_settle_records_the_native_outcome <- function()
{
    world(); settings();
    local weapon = skill(70), trial = X.price(weapon, actor(1), actor(2), true);
    X.settle(trial, true);
    X.settle(X.price(weapon, actor(1), actor(2), false), false);
    check(X.Battle.ours.n == 2 && X.Battle.ours.hits == 1 && near(X.Battle.ours.sumP, 1.4, 1e-6), "recorded");
    check(weapon.priced == 2 && ::Errors.len() == 0, "priced once per attack without errors");
    check(X.price(skill(70), actor(2), actor(3), true) == null, "excluded attack prices to nothing");
    settings({Enabled = false});
    local off = skill(70);
    check(X.price(off, actor(1), actor(2), true) == null && off.priced == 0, "disabled meter neither prices nor records");
};

cases.capture_failures_are_logged_not_thrown <- function()
{
    world(); settings();
    local broken = skill(70); broken.getHitchance = function( _t ) { throw "pricing exploded"; };
    check(X.price(broken, actor(1), actor(2), true) == null, "failed pricing yields no trial");
    check(::Errors.len() == 1 && ::Errors[0].find("pricing exploded") != null, "failure logged");
    X.push = function() { throw "push exploded"; };
    X.settle({side = "ours", p = 0.7}, true);
    check(X.Battle.ours.n == 1 && ::Errors.len() == 2, "attack recorded before the push failed, failure logged");
};

cases.capture_consumes_no_rng <- function()
{
    world(); settings();
    local rolls = 0;
    ::Math.rand = function( _a, _b ) { rolls++; return 50; };
    local trial = X.price(skill(70), actor(1), actor(2), true);
    local hit = ::Math.rand(1, 100) <= 70;
    X.settle(trial, hit);
    check(rolls == 1 && X.Battle.ours.hits == 1 && ::Errors.len() == 0, "only the native path rolled");
};

return cases;
