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
    check(near(X.summary().rarity, 75.0, 0.0001) && near(X.summary().marker, 50.0 + 25.0 / 6.0, 0.0001), "two heads: upper tail 1/4, weight 2/12");
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
    check(near(s.rarity, 5.0, 0.0001) && near(s.marker, 50.0 - 45.0 / 11.0, 0.0001), "rare miss is weighted 1/11");
    X.reset(); X.record("ours", 0.05, true);
    s = X.summary();
    check(s.ours.percent == "+1900%" && s.ours.tone == "good", "no positive cap or percent damping");
    check(near(s.rarity, 95.0, 0.0001) && near(s.marker, 50.0 + 45.0 / 11.0, 0.0001), "rare hit is weighted 1/11");
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

cases.fractional_percentages_and_swings_round_on_the_float <- function()
{
    // Engine Math.abs truncates; the fixture emulates it, so these fail with native abs.
    feed("ours", [70, 70], [1, 0]);
    check(X.summary().ours.percent == "-29%", "1/1.40 is -28.57%, not -28%");
    X.reset(); feed("ours", [70, 70, 70], [1, 1, 1]);
    check(X.summary().ours.percent == "+43%", "3/2.10 is +42.86%, not +42%");
    X.reset(); X.record("ours", 0.61, true);
    check(X.summary().ours.percent == "+64%", "1/0.61 is +63.93%, not +63%");
    X.reset(); feed("ours", array(5, 2), array(5, 1));
    local s = X.summary();
    check(s.ours.percent == "+4900%" && near(s.swing, 4.9, 0.00001), "5/0.10 hits");
    check(X.swingText(s.swing) == "Net hit swing: 4.90 hits in your favour.", "swing keeps two decimals");
    check(X.swingText(-0.39, "Net") == "Net: 0.39 hits against you." && X.swingText(0.004, "Net") == "Net: even.", "fractional swing is not even");
};

cases.live_marker_weights_evidence_smoothly_and_emphasis_warms_by_ten <- function()
{
    for (local n = 1; n <= 30; n++)
    {
        X.record(n % 2 == 0 ? "ours" : "theirs", 0.5, n % 2 == 0);
        local s = X.summary(), weight = n / (n + 10.0), warmup = n < 10 ? n / 10.0 : 1.0;
        local raw = n == 1 ? 50.0 : 100.0 * (1.0 - ::Math.pow(0.5, n));
        check(near(s.rarity, raw, 0.0001), "exact all-favorable tail");
        check(near(s.weight, weight, 0.00001) && near(s.marker, 50.0 + (raw - 50.0) * weight, 0.0001), "evidence weight " + n);
        check(near(s.emphasis, 0.5 + 0.5 * warmup, 0.00001), "visual emphasis " + n);
        if (raw != 50.0) check((s.marker > 50.0) == (raw > 50.0) && s.marker != raw, "same side as the tail, never the raw tail");
        if (n >= 10) check(s.emphasis == 1.0 && s.weight < 1.0, "full emphasis while evidence still weighs");
    }
    check(near(X.summary().weight, 0.75, 0.00001), "three quarters at attack 30");
    // Two high-chance misses from near neutral: the old cutoff exposed the full tail jump.
    X.reset(); feed("ours", [90, 90], [0, 0]);
    local s = X.summary();
    check(near(s.rarity, 1.0, 0.0001) && near(s.marker, 50.0 - 49.0 / 6.0, 0.0001), "1% tail moves the bar 8.17 points, not 9.8");
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
    check(s.text == "Bottom 21% of outcomes at these odds", "round group upward");
    X.reset(); X.record("ours", 0.95, false);
    check(X.summary().text == "Bottom 5% of outcomes at these odds", "float drift must not enlarge an integer group");
    X.reset(); feed("ours", array(10, 5), array(10, 1));
    check(X.summary().text == "Top 1% of outcomes at these odds", "minimum displayed group");
};

cases.long_battle_normalizes_float_drift_and_stays_finite <- function()
{
    for (local i = 0; i < 1000; i++) X.record("ours", 0.5, i % 2 == 0);
    check(X.summary().rarity == 50.0, "symmetric long battle");
    foreach (i, value in X.Battle.mass) X.Battle.mass[i] = value * 1.001;
    check(X.summary().rarity == 50.0, "normalize accumulated mass");
};

return cases;
