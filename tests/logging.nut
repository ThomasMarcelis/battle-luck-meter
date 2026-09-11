local X = ::XBro, cases = {};

function lines( _event = null )
{
    local out = [];
    foreach (line in ::Logs)
    {
        check(line.find("[xBro] battle=") == 0 && line.find("<") == null, "prefixed, single line, no markup: " + line);
        local f = fields(line);
        if (_event == null ? ("attack" in f) : f.event == _event) out.push(f);
    }
    return out;
}

cases.begin_numbers_battles_and_writes_a_start_line <- function()
{
    X.record("ours", 0.5, true);
    local first = X.Battle.id;
    X.begin();
    check(X.Battle.id == first + 1 && X.Battle.ours.n == 0, "next id, accumulators wiped");
    X.begin();
    local starts = lines("start");
    check(starts.len() == 2 && starts[1].battle == "" + (first + 2) && starts[1].version == X.Version, "one start line per battle with the version");
    X.reset();
    check(X.Battle.id == first + 2 && ::Logs.len() == 2, "reset keeps the number and logs nothing");
};

cases.each_settled_attack_writes_one_parseable_line <- function()
{
    world(); settings();
    X.begin();
    X.settle(X.price(skill(70), actor(1), actor(2), true), true);
    X.settle(X.price(skill(35, true), actor(3), actor(1), true), false);
    local a = lines();
    check(a.len() == 2 && a[0].battle == "" + X.Battle.id && a[0].attack == "1" && a[1].attack == "2", "numbered within the battle");
    check(a[0].side == "ours" && a[0].hit == "1" && a[0].chance == "70" && a[0].p == "0.700000", "our hit at the engine chance");
    check(a[0].skill == "Slash" && a[0].by == "Our Bro" && a[0].on == "Foe 2", "who did what to whom");
    check(a[1].side == "theirs" && a[1].hit == "0" && a[1].chance == "35" && a[1].p == "0.350000" && a[1].skill == "Quick Shot", "their miss");
    world(null, 0);
    local lucky = actor(1); lucky.reroll = 10;
    X.settle(X.price(skill(50), actor(2), lucky, true), true);
    a = lines();
    check(a[2].chance == "50" && a[2].p == "0.425250", "engine chance stays raw; p carries the beginner shift and the reroll");
};

cases.the_update_and_the_log_line_never_block_each_other <- function()
{
    world(); settings();
    local live = {pushed = 0, isNull = @() false, xbroPush = function( _data ) { this.pushed++; }};
    ::Tactical.TopbarRoundInformation = live;
    ::logInfo = function( _text ) { throw "log.html on fire"; };
    X.settle(X.price(skill(70), actor(1), actor(2), true), true);
    check(X.Battle.ours.hits == 1 && live.pushed == 1, "recorded and pushed although the log failed");
    check(::Errors.len() == 1 && ::Errors[0].find("log.html on fire") != null, "log failure reported through logError");
    ::logInfo = function( _text ) { ::Logs.push(_text); };
    X.push = function() { throw "push exploded"; };
    X.settle(X.price(skill(70), actor(1), actor(2), true), false);
    check(X.Battle.ours.n == 2 && ::Logs.len() == 1 && fields(::Logs[0]).hit == "0", "recorded and logged although the push failed");
    local nameless = actor(2); nameless.getName = function() { throw "no name"; };
    X.settle(X.price(skill(70), actor(1), nameless, true), true);
    check(X.Battle.ours.n == 3 && fields(::Logs[1]).on == "?", "an unreadable name is logged as ? and the attack still counts");
};

cases.battle_end_writes_the_tooltip_numbers <- function()
{
    settings();
    feed("theirs", [35, 6, 50, 82, 82, 64, 21, 18], [1, 0, 1, 1, 1, 1, 1, 1]);
    X.finish();
    local e = lines("end");
    check(e.len() == 1 && e[0].battle == "" + X.Battle.id, "one end line");
    check(e[0].ours_n == "0" && e[0].ours_hits == "0" && e[0].ours_expected == "0.000", "our side");
    check(e[0].theirs_n == "8" && e[0].theirs_hits == "7" && e[0].theirs_expected == "3.580", "their side");
    check(near(e[0].z.tofloat(), -2.92, 0.005) && e[0].rank == "99" && e[0].pending == "0" && e[0].min_attacks == "8" && e[0].text == "Unlucky 99%", "verdict " + ::Logs.top());
    settings({MinAttacks = 12});
    X.finish();
    e = lines("end");
    check(e[1].pending == "1" && e[1].min_attacks == "12" && e[1].text == "", "pending verdict is logged as pending");
};

// Acceptance: with only the attack lines, a reader rebuilds the battle and lands on the same end line.
cases.end_line_is_reproducible_from_the_attack_lines <- function()
{
    world(null, 0); settings();
    local lucky = actor(1); lucky.reroll = 10;
    local script = [[skill(82), actor(1), actor(2), true], [skill(64), actor(1), actor(2), false], [skill(35, true), actor(2, 3), actor(1), true],
        [skill(50), actor(3), lucky, true], [skill(21), actor(2), lucky, false], [skill(95), actor(1), actor(3), true],
        [skill(6), actor(2), actor(1), true], [skill(60, true, true), actor(1, 4), actor(2), true], [skill(18), actor(2), actor(1), false]];
    X.begin();
    foreach (step in script) X.settle(X.price(step[0], step[1], step[2], true), step[3]);
    X.finish();
    local written = ::Logs.top(), attacks = lines();
    check(attacks.len() == 9, "every attack reached the log");
    X.begin();
    foreach (a in attacks) X.record(a.side, a.p.tofloat(), a.hit == "1");
    X.finish();
    local rebuilt = fields(::Logs.top()), original = fields(written);
    foreach (key, value in original) if (key != "battle") check(rebuilt[key] == value, key + ": " + value + " rebuilt as " + rebuilt[key]);
    check(original.theirs_n == "5" && original.ours_hits == "3" && original.text != "", "scenario exercised both sides and a verdict");
};

return cases;
