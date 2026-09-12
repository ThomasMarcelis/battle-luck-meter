local X = ::XBro, cases = {};

cases.inclusive_tails_keep_common_outcomes_neutral <- function()
{
    check(X.summary().rarity == 50.0 && X.summary().ours.percent == "—", "empty battle");
    foreach (hit in [false, true])
    {
        X.reset(); X.record("ours", 0.5, hit);
        check(X.summary().rarity == 50.0 && X.summary().marker == 50.0, "one coin flip is common");
    }
    X.record("ours", 0.5, true);
    check(near(X.summary().rarity, 75.0, 0.0001) && near(X.summary().marker, 55.0, 0.0001), "two heads: upper tail 1/4");
    X.reset(); feed("ours", array(8, 50), [1, 1, 1, 1, 1, 1, 0, 0]);
    check(near(X.summary().rarity, 85.546875, 0.0001), "6/8: upper tail 37/256");
    X.reset(); feed("ours", array(8, 95), array(8, 1));
    check(X.summary().rarity == 50.0, "eight likely hits remain common");
    X.reset(); feed("ours", array(10, 100), array(10, 1));
    check(X.summary().rarity == 50.0 && X.summary().marker == 50.0, "certain outcomes");
};

cases.percentages_are_immediate_undamped_and_player_coloured <- function()
{
    X.record("ours", 0.95, false);
    local s = X.summary();
    check(s.ours.percent == "-100%" && s.ours.tone == "bad" && s.theirs.percent == "—", "first miss visible");
    check(near(s.rarity, 5.0, 0.0001) && near(s.marker, 45.5, 0.0001), "rare miss is damped");
    X.reset(); X.record("ours", 0.05, true);
    s = X.summary();
    check(s.ours.percent == "+1900%" && s.ours.tone == "good", "no positive cap or percent damping");
    check(near(s.rarity, 95.0, 0.0001) && near(s.marker, 54.5, 0.0001), "rare hit is damped");
    X.reset(); feed("ours", array(4, 40), [1, 1, 1, 0]);
    check(X.summary().ours.percent == "+88%", "float32 half rounds away from zero");
    X.record("theirs", 0.5, true);
    check(X.summary().theirs.percent == "+100%" && X.summary().theirs.tone == "bad", "enemy surplus is red");
    X.reset(); X.record("theirs", 0.5, false);
    check(X.summary().theirs.tone == "good", "enemy deficit is green");
    X.reset(); X.record("ours", 0.0, false);
    check(X.summary().ours.percent == "—" && X.summary().ours.tone == "neutral", "undefined ratio");
    X.reset(); X.record("ours", 0.999, true);
    check(X.summary().ours.percent == "0%" && X.summary().ours.tone == "neutral", "rounded positive zero");
    X.record("ours", 0.002, false);
    check(X.summary().ours.percent == "0%" && X.summary().ours.tone == "neutral", "rounded negative zero");
};

cases.damping_decreases_linearly_and_is_gone_at_ten <- function()
{
    for (local n = 1; n <= 12; n++)
    {
        X.record(n % 2 == 0 ? "ours" : "theirs", 0.5, n % 2 == 0);
        local s = X.summary(), weight = n < 10 ? n / 10.0 : 1.0;
        local raw = n == 1 ? 50.0 : 100.0 * (1.0 - ::Math.pow(0.5, n));
        check(near(s.rarity, raw, 0.0001), "exact all-favorable tail");
        check(near(s.weight, weight, 0.00001) && near(s.marker, 50.0 + (raw - 50.0) * weight, 0.0001), "linear warm-up " + n);
        check(near(s.emphasis, 0.5 + 0.5 * weight, 0.00001), "visual emphasis");
        if (n >= 10) check(s.marker == s.rarity && s.weight == 1.0, "no residual damping");
    }
};

cases.mixed_odds_match_hand_enumeration_and_order_and_side_symmetry <- function()
{
    // q=.2,.7,.6 gives mass [.096,.392,.428,.084]; observed F=1 => lower=.488.
    X.record("ours", 0.2, true); X.record("ours", 0.7, false); X.record("theirs", 0.4, true);
    local s = X.summary();
    foreach (i, want in [0.096, 0.392, 0.428, 0.084]) check(near(X.Battle.mass[i], want, 0.00001), "probability mass");
    check(near(s.rarity, 48.8, 0.0001), "inclusive mixed lower tail");
    X.reset(); X.record("theirs", 0.4, true); X.record("ours", 0.7, false); X.record("ours", 0.2, true);
    check(near(X.summary().rarity, s.rarity, 0.0001), "order invariance");
    X.reset(); X.record("theirs", 0.2, true); X.record("theirs", 0.7, false); X.record("ours", 0.4, true);
    check(near(X.summary().rarity, 100.0 - s.rarity, 0.0001), "swap sides reverses luck");
    X.reset(); check(X.Battle.mass.len() == 1 && X.Battle.mass[0] == 1.0, "distribution belongs to battle");
};

cases.existing_battle_reports_hit_deficits_and_conservative_rarity_group <- function()
{
    feed("ours", [82,82,64,64,60,60,55,55,50,50,50,50,68], [1,0,1,0,1,0,1,0,1,0,1,0,0]);
    feed("theirs", [35,35,50,50,50,50,55,55,60,60,60,60,55,55], [1,1,1,1,1,1,1,1,0,0,0,0,0,0]);
    local s = X.summary();
    check(s.ours.percent == "-24%" && s.theirs.percent == "+10%", "relative hit counts");
    check(s.ours.tone == "bad" && s.theirs.tone == "bad", "both hurt the player");
    check(near(s.swing, -2.6, 0.00001) && near(s.rarity, 20.2055, 0.0001), "net swing and exact rarity");
    check(s.text == "Bottom 21% unluckiest battles", "round group upward");
    X.reset(); X.record("ours", 0.95, false);
    check(X.summary().text == "Bottom 5% unluckiest battles", "float drift must not enlarge an integer group");
    X.reset(); feed("ours", array(10, 5), array(10, 1));
    check(X.summary().text == "Top 1% luckiest battles", "minimum displayed group");
};

cases.long_battle_normalizes_float_drift_and_stays_finite <- function()
{
    for (local i = 0; i < 1000; i++) X.record("ours", 0.5, i % 2 == 0);
    check(X.summary().rarity == 50.0, "symmetric long battle");
    foreach (i, value in X.Battle.mass) X.Battle.mass[i] = value * 1.001;
    check(X.summary().rarity == 50.0, "normalize accumulated mass");
};

return cases;
