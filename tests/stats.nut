local X = ::XBro, cases = {};
local helderChances = [35, 6, 50, 82, 82, 64, 21, 18], helderHits = [1, 0, 1, 1, 1, 1, 1, 1];

cases.helder_sequence_against_us_is_a_three_sigma_unlucky_battle <- function()
{
    feed("theirs", helderChances, helderHits);
    local s = X.summary(8);
    check(near(s.theirs.expected, 3.58, 0.005), "expected hits " + s.theirs.expected);
    check(near(::Math.pow(X.Battle.theirs.sumPQ, 0.5), 1.17, 0.005), "sd " + X.Battle.theirs.sumPQ);
    check(near(s.z, -2.92, 0.01), "z " + s.z);
    check(s.theirs.hits == 7 && s.theirs.n == 8 && s.ours.n == 0, "counts");
    check(!s.pending && s.text == "Unlucky 99%" && s.rank == 99, "readout " + s.text);
    check(s.offset < -0.85 && s.offset > -0.95, "unlucky offset is negative: " + s.offset);
};

cases.same_sequence_by_us_mirrors_to_lucky <- function()
{
    feed("ours", helderChances, helderHits);
    local s = X.summary(8);
    check(near(s.z, 2.92, 0.01) && s.text == "Lucky 99%", "mirror " + s.text);
    feed("theirs", helderChances, helderHits);
    s = X.summary(8);
    check(near(s.z, 0.0, 1e-6) && s.text == "Even", "both sides equally lucky must cancel: " + s.text);
};

cases.normal_cdf_matches_tables <- function()
{
    foreach (z, p in {[0.0] = 0.5, [0.5] = 0.6915, [1.0] = 0.8413, [1.5] = 0.9332, [2.0] = 0.9772, [2.5] = 0.9938, [-1.0] = 0.1587, [-2.5] = 0.0062})
        check(near(X.normalCdf(z), p, 0.0001), "cdf(" + z + ") = " + X.normalCdf(z));
};

cases.offset_is_bounded_tanh <- function()
{
    check(X.tanh(0.0) == 0.0 && near(X.tanh(1.0), 0.7616, 0.0005) && near(X.tanh(-1.0), -0.7616, 0.0005), "tanh values");
    check(X.tanh(50.0) == 1.0 && X.tanh(-50.0) == -1.0 && X.tanh(5.0) < 1.0, "saturation");
    feed("ours", [95, 95, 95, 95, 95, 95, 95, 95], [1, 1, 1, 1, 1, 1, 1, 1]);
    feed("theirs", [5, 5, 5, 5, 5, 5, 5, 5], [0, 0, 0, 0, 0, 0, 0, 0]);
    local s = X.summary(8);
    check(s.offset > 0.0 && s.offset < 1.0, "offset stays inside the bar: " + s.offset);
};

cases.zero_variance_and_empty_battle_are_neutral <- function()
{
    local s = X.summary(8);
    check(s.pending && s.z == 0.0 && s.offset == 0.0 && s.text == "" && s.n == 0, "empty");
    feed("ours", [100, 100, 100, 100, 100, 100, 100, 100], [1, 1, 1, 1, 1, 1, 1, 1]);
    s = X.summary(8);
    check(!s.pending && s.z == 0.0 && s.text == "Even", "certain hits carry no luck: " + s.text);
};

cases.threshold_and_neutral_band <- function()
{
    feed("ours", [50, 50, 50, 50], [1, 1, 1, 1]);
    feed("theirs", [50, 50, 50], [0, 0, 0]);
    local s = X.summary(8);
    check(s.pending && s.text == "" && s.offset == 0.0 && near(s.z, 2.646, 0.01), "seven attacks stay pending");
    X.record("theirs", 0.5, false);
    s = X.summary(8);
    check(!s.pending && s.text == "Lucky 99%", "eighth attack unlocks the verdict: " + s.text);
    check(X.summary(9).pending, "threshold is the setting");
    X.reset();
    feed("ours", [50, 50, 50, 50, 50, 50, 50, 50], [1, 0, 1, 0, 1, 0, 1, 1]);
    s = X.summary(8);
    check(near(s.z, 0.707, 0.01) && s.text == "Lucky 76%", "z just above the band: " + s.text);
    X.reset();
    feed("ours", [50, 50, 50, 50, 50, 50, 50, 50], [1, 0, 1, 0, 1, 0, 1, 0]);
    check(X.summary(8).text == "Even", "|z| < 0.5 reads Even");
    X.reset();
    feed("theirs", [50, 50, 50, 50, 50, 50, 50, 50], [1, 0, 1, 0, 1, 0, 1, 1]);
    check(X.summary(8).text == "Unlucky 76%", "unlucky wording");
};

return cases;
