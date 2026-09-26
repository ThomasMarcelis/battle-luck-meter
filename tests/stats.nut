local X = ::BattleLuckMeter, cases = {};

cases.inclusive_tails_keep_common_outcomes_neutral <- function()
{
    check(X.summary().rarity == 50.0 && X.summary().ours.percent == "—", "empty battle");
    foreach (hit in [false, true])
    {
        X.reset(); X.record("ours", 0.5, hit);
        check(X.summary().rarity == 50.0, "one coin flip is common");
    }
    X.record("ours", 0.5, true);
    check(near(X.summary().rarity, 75.0, 0.0001) && near(X.summary().marker, 53.195591, 0.0002), "two heads: upper tail 1/4, weight 2/12");
    X.reset(); feed("ours", array(8, 50), [1, 1, 1, 1, 1, 1, 0, 0]);
    check(near(X.summary().rarity, 85.546875, 0.0001), "6/8: upper tail 37/256");
    X.reset(); feed("ours", array(8, 95), array(8, 1));
    check(X.summary().rarity == 50.0, "eight likely hits remain common");
    X.reset(); feed("ours", array(10, 100), array(10, 1));
    check(X.summary().rarity == 50.0 && X.summary().marker == 50.0, "certain outcomes");
};

cases.probit_matches_known_quantiles_and_saturates_at_three_sigma <- function()
{
    check(X.probit(0.5) == 0.0, "the median is the centre of the axis");
    foreach (pair in [[0.75, 0.674490], [0.975, 1.959964], [0.025, -1.959964], [0.8413447460685429, 1.0],
        [0.15865525393145707, -1.0], [0.9986501019683699, 3.0], [0.0013498980316301035, -3.0], [0.005, -2.575829]])
        check(near(X.probit(pair[0]), pair[1], 0.001), "inverse normal at " + pair[0]);
    // Clipped at exactly Phi(-+3), so the axis saturates instead of diverging.
    check(X.probit(0.0) == X.probit(0.0013498980316301035), "lower clip");
    check(X.probit(1.0) == X.probit(1.0 - 0.0013498980316301035), "upper clip");
    check(X.probit(1.0e-12) == X.probit(0.0) && X.probit(-5.0) == X.probit(0.0), "nothing below the clip can diverge");
    check(near(X.probit(0.3) + X.probit(0.7), 0.0, 0.00002), "odd symmetry about the median");
    // Cancellation near the clip costs the float32 evaluation a little monotonicity:
    // the worst measured reversal is 0.00125 sigma, a fiftieth of a bar point.
    local previous = -4.0;
    for (local i = 0; i <= 400; i++)
    {
        local z = X.probit(i / 400.0);
        check(z >= previous - 0.002 && z >= -3.0 && z <= 3.0, "rises across the track and stays bounded at " + i);
        previous = z;
    }
    check(near(X.probit(1.0), 2.9994, 0.0002) && near(X.probit(0.0), -2.9993, 0.0002), "the clip alone keeps the axis inside three sigma");
};

cases.live_marker_uses_the_mid_p_tail_on_a_sigma_axis <- function()
{
    local s = X.summary();
    check(s.midp == 0.5 && s.z == 0.0 && s.marker == 50.0, "an empty battle sits at the centre");
    X.record("ours", 0.5, true);
    s = X.summary();
    check(s.rarity == 50.0 && near(s.midp, 0.75, 1e-7), "mid-p splits the observed bin instead of pinning at the median");
    check(near(s.marker, 51.02195, 0.0002), "one coin flip leaves the centre by a sigma step, not a percentile jump");
    X.record("ours", 0.5, false);
    s = X.summary();
    check(s.midp == 0.5 && s.z == 0.0 && s.marker == 50.0, "a count sitting at the median is exactly neutral");
    X.reset(); feed("ours", array(8, 95), array(8, 1));
    s = X.summary();
    check(s.rarity == 50.0 && near(s.midp, 0.66828978, 1e-6) && near(s.marker, 53.22374, 0.0002), "mid-p moves where the percentile stayed pinned");
    X.reset(); feed("ours", array(8, 50), [1, 1, 1, 1, 1, 1, 0, 0]);
    check(near(X.summary().midp, 0.91015625, 1e-6) && near(X.summary().marker, 59.938274, 0.0002), "6/8 at even odds");
};

cases.sigma_axis_saturates_instead_of_running_off_the_bar <- function()
{
    feed("ours", array(4, 99), array(4, 0));
    local s = X.summary();
    check(near(s.z, -2.9993, 0.0002) && near(s.marker, 35.717613, 0.0002), "four 99% misses clip at three sigma");
    X.record("ours", 0.99, false);
    local t = X.summary();
    check(t.z == s.z && near(t.marker, 33.337219, 0.0002), "beyond the clip only the evidence weight moves the bar");
    check(t.marker > 0.0 && t.marker < 100.0, "the marker never leaves the track");
    X.reset(); feed("theirs", array(4, 99), array(4, 0));
    check(near(X.summary().marker, 64.282867, 0.0002), "enemy misses saturate on the lucky side");
};

cases.percentages_are_immediate_undamped_and_player_coloured <- function()
{
    X.record("ours", 0.95, false);
    local s = X.summary();
    check(s.ours.exactPercent == "-100%" && s.ours.exactTone == "bad" && s.theirs.exactPercent == "—", "first miss visible");
    check(near(s.rarity, 5.0, 0.0001) && near(s.marker, 47.030373, 0.0002), "rare miss on the sigma axis at weight 1/11");
    X.reset(); X.record("ours", 0.05, true);
    s = X.summary();
    check(s.ours.exactPercent == "+1900%" && s.ours.exactTone == "good", "no positive cap on the exact figure");
    check(near(s.rarity, 95.0, 0.0001) && near(s.marker, 52.969639, 0.0002), "rare hit on the sigma axis at weight 1/11");
    X.reset(); feed("ours", array(4, 40), [1, 1, 1, 0]);
    check(X.summary().ours.exactPercent == "+88%", "float32 half rounds away from zero");
    X.record("theirs", 0.5, true);
    check(X.summary().theirs.exactPercent == "+100%" && X.summary().theirs.exactTone == "bad", "enemy surplus is red");
    X.reset(); X.record("theirs", 0.5, false);
    check(X.summary().theirs.exactTone == "good", "enemy deficit is green");
    X.reset(); X.record("ours", 0.0, false);
    check(X.summary().ours.exactPercent == "—" && X.summary().ours.exactTone == "neutral", "undefined ratio");
    X.reset(); X.record("ours", 0.999, true);
    check(X.summary().ours.exactPercent == "0%" && X.summary().ours.exactTone == "neutral", "rounded positive zero");
    X.record("ours", 0.002, false);
    check(X.summary().ours.exactPercent == "0%" && X.summary().ours.exactTone == "neutral", "rounded negative zero");
};

cases.live_badges_weight_each_side_by_its_own_evidence <- function()
{
    X.record("ours", 0.35, true);
    local s = X.summary();
    check(s.ours.exactPercent == "+186%" && s.ours.percent == "+17%", "one lucky hit reads +186% exactly, +17% live");
    check(s.ours.tone == "good" && s.ours.tone == s.ours.exactTone, "weighting never changes the side of zero");
    check(s.theirs.percent == "—" && s.theirs.exactPercent == "—", "an empty side has no comparison either way");
    X.reset(); X.record("ours", 0.95, false);
    check(X.summary().ours.percent == "-9%" && X.summary().ours.exactPercent == "-100%", "the -100% floor is weighted too");
    X.reset(); X.record("theirs", 0.5, true);
    s = X.summary();
    check(s.theirs.percent == "+9%" && s.theirs.tone == "bad" && s.theirs.exactPercent == "+100%", "enemy badges keep their reversed colour");
    X.reset(); feed("ours", array(10, 70), array(10, 1));
    check(X.summary().ours.percent == "+21%" && X.summary().ours.exactPercent == "+43%", "half weight at that side's tenth attack");
    // Each side carries its own count, so a busy side is trusted more than a quiet one.
    X.record("theirs", 0.5, true);
    s = X.summary();
    check(s.ours.percent == "+21%" && s.theirs.percent == "+9%", "sides weight independently");
    X.reset(); feed("ours", array(4, 40), [1, 1, 1, 0]);
    check(X.summary().ours.percent == "+25%" && X.summary().ours.exactPercent == "+88%", "weighted rounding stays on the float");
    X.reset(); X.record("ours", 0.999, true);
    check(X.summary().ours.percent == "0%" && X.summary().ours.tone == "neutral", "a weighted rounded zero is neutral");
};

cases.fractional_percentages_and_swings_round_on_the_float <- function()
{
    // Engine Math.abs truncates; the fixture emulates it, so these fail with native abs.
    feed("ours", [70, 70], [1, 0]);
    check(X.summary().ours.exactPercent == "-29%" && X.summary().ours.percent == "-5%", "1/1.40 is -28.57%, not -28%");
    X.reset(); feed("ours", [70, 70, 70], [1, 1, 1]);
    check(X.summary().ours.exactPercent == "+43%" && X.summary().ours.percent == "+10%", "3/2.10 is +42.86%, not +42%");
    X.reset(); X.record("ours", 0.61, true);
    check(X.summary().ours.exactPercent == "+64%" && X.summary().ours.percent == "+6%", "1/0.61 is +63.93%, not +63%");
    X.reset(); feed("ours", array(5, 2), array(5, 1));
    local s = X.summary();
    check(s.ours.exactPercent == "+4900%" && s.ours.percent == "+1633%" && near(s.swing, 4.9, 0.00001), "5/0.10 hits");
    check(X.swingText(s.swing) == "Net hit swing: 4.90 hits in your favour.", "swing keeps two decimals");
    check(X.swingText(-0.39, "Net") == "Net: 0.39 hits against you." && X.swingText(0.004, "Net") == "Net: even.", "fractional swing is not even");
};

cases.live_marker_weights_evidence_smoothly_and_emphasis_warms_by_ten <- function()
{
    local previous = 50.0, biggest = 0.0;
    for (local n = 1; n <= 30; n++)
    {
        X.record(n % 2 == 0 ? "ours" : "theirs", 0.5, n % 2 == 0);
        local s = X.summary(), weight = n / (n + 10.0), warmup = n < 10 ? n / 10.0 : 1.0;
        local raw = n == 1 ? 50.0 : 100.0 * (1.0 - ::Math.pow(0.5, n));
        // Every trial so far is favorable, so the mid-p tail is 1 - 0.5^(n+1) by hand.
        local midp = 1.0 - ::Math.pow(0.5, n + 1);
        check(near(s.rarity, raw, 0.0001), "exact all-favorable tail");
        check(near(s.midp, midp, 0.0000001), "hand-computed mid-p tail " + n);
        check(near(s.weight, weight, 0.00001), "evidence weight " + n);
        check(near(s.marker, 50.0 + (50.0 / 3.0) * X.probit(midp) * weight, 0.0001), "sigma axis times evidence weight " + n);
        check(near(s.emphasis, 0.5 + 0.5 * warmup, 0.00001), "visual emphasis " + n);
        check(s.marker > previous && s.marker < 100.0, "an unbroken lucky run only ever climbs, and stays on the track");
        if (s.marker - previous > biggest) biggest = s.marker - previous;
        previous = s.marker;
        if (n >= 9) check(s.z == X.probit(1.0), "the axis is saturated once the tail passes three sigma");
        if (n >= 10) check(s.emphasis == 1.0 && s.weight < 1.0, "full emphasis while evidence still weighs");
    }
    check(near(X.summary().weight, 0.75, 0.00001), "three quarters at attack 30");
    check(biggest < 3.2, "an unbroken even-odds lucky run never moves the bar more than 3.2 points in one attack");
    // Two high-chance misses from near neutral: on a percentile axis this was a 8.17 point step.
    X.reset(); feed("ours", [90, 90], [0, 0]);
    local s = X.summary();
    check(near(s.rarity, 1.0, 0.0001) && near(s.marker, 42.8451, 0.0002), "1% tail is 2.58 sigma, 7.15 bar points at weight 2/12");
};

cases.mixed_odds_match_hand_enumeration_and_order_and_side_symmetry <- function()
{
    // q=.2,.7,.6 gives mass [.096,.392,.428,.084]; observed F=1 => lower=.488.
    X.record("ours", 0.2, true); X.record("ours", 0.7, false); X.record("theirs", 0.4, true);
    local s = X.summary();
    foreach (i, want in [0.096, 0.392, 0.428, 0.084]) check(near(X.Battle.mass[i], want, 0.00001), "probability mass");
    check(near(s.rarity, 48.8, 0.0001), "inclusive mixed lower tail");
    check(near(s.midp, 0.292, 0.0000001) && near(s.marker, 47.893929, 0.0002), "mid-p is 0.096 plus half of 0.392");
    X.reset(); X.record("theirs", 0.4, true); X.record("ours", 0.7, false); X.record("ours", 0.2, true);
    check(near(X.summary().rarity, s.rarity, 0.0001) && near(X.summary().marker, s.marker, 0.0002), "order invariance");
    X.reset(); X.record("theirs", 0.2, true); X.record("theirs", 0.7, false); X.record("ours", 0.4, true);
    check(near(X.summary().rarity, 100.0 - s.rarity, 0.0001), "swap sides reverses luck");
    check(near(X.summary().midp, 1.0 - s.midp, 0.000001) && near(X.summary().marker, 100.0 - s.marker, 0.0005), "mid-p sums to one across the two sides");
    X.reset(); check(X.Battle.mass.len() == 1 && X.Battle.mass[0] == 1.0, "distribution belongs to battle");
};

cases.existing_battle_reports_hit_deficits_and_conservative_rarity_group <- function()
{
    feed("ours", [82,82,64,64,60,60,55,55,50,50,50,50,68], [1,0,1,0,1,0,1,0,1,0,1,0,0]);
    feed("theirs", [35,35,50,50,50,50,55,55,60,60,60,60,55,55], [1,1,1,1,1,1,1,1,0,0,0,0,0,0]);
    local s = X.summary();
    check(s.ours.exactPercent == "-24%" && s.theirs.exactPercent == "+10%", "relative hit counts");
    check(s.ours.percent == "-14%" && s.theirs.percent == "+6%", "live badges weighted 13/23 and 14/24");
    check(s.ours.tone == "bad" && s.theirs.tone == "bad", "both hurt the player");
    check(near(s.swing, -2.6, 0.00001) && near(s.rarity, 20.2055, 0.0001), "net swing and exact rarity");
    check(near(s.midp, 0.155647195, 0.0000001) && near(s.marker, 37.68528, 0.0002), "mid-p tail is about one sigma against");
    check(s.text == "Bottom 21% vs aimed odds", "round group upward");
    X.reset(); X.record("ours", 0.95, false);
    check(X.summary().text == "Bottom 5% vs aimed odds", "float drift must not enlarge an integer group");
    X.reset(); feed("ours", array(10, 5), array(10, 1));
    check(X.summary().text == "Top 1% vs aimed odds", "minimum displayed group");
};

cases.long_battle_normalizes_float_drift_and_stays_finite <- function()
{
    for (local i = 0; i < 1000; i++) X.record("ours", 0.5, i % 2 == 0);
    check(X.summary().rarity == 50.0 && near(X.summary().midp, 0.5, 0.000001) && near(X.summary().marker, 50.0, 0.0002), "symmetric long battle");
    foreach (i, value in X.Battle.mass) X.Battle.mass[i] = value * 1.001;
    check(X.summary().rarity == 50.0 && near(X.summary().midp, 0.5, 0.000001), "normalize accumulated mass");
};

return cases;
