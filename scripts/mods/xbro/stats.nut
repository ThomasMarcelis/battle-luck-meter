::XBro.record <- function( _side, _p, _hit )
{
    local side = this.Battle[_side];
    side.n++;
    if (_hit) side.hits++;
    side.sumP += _p;
    side.sumPQ += _p * (1.0 - _p);

    // Favorable outcomes are our hits and enemy misses. Update the distribution
    // once per counted attack, descending so each term reads the previous state.
    local q = _side == "ours" ? _p : 1.0 - _p, mass = this.Battle.mass;
    mass.push(0.0);
    for (local k = mass.len() - 1; k > 0; k--)
        mass[k] = mass[k] * (1.0 - q) + mass[k - 1] * q;
    mass[0] *= 1.0 - q;
};

// The bar is drawn on a standard-deviation axis: +-3 sigma spans the track, so one
// attack is worth the same number of bar points wherever the marker currently sits.
// A percentile axis is steepest at the centre, which is what made the bar lurch.
::XBro.SIGMA_SCALE <- 50.0 / 3.0;
// Phi(-3): clipping the tail here saturates the axis instead of letting it diverge.
::XBro.PROBIT_CLIP <- 0.0013498980316301035;
// Central rational approximation of the inverse normal CDF in r = q * q, q = p - 0.5.
// A survey of 98 decompiled vanilla scripts found Math.minf, Math.maxf, Math.pow, Math.abs
// and Math.floor in use and no call to Math.sqrt or Math.log, so neither is assumed to
// exist or to be float-correct; this needs only multiply, divide and add. Accurate to
// 4.1e-4 sigma in double precision and 8.6e-4 sigma (0.015 bar points) in float32 over
// the clipped range, which is the whole axis.
::XBro.PROBIT_P <- [2.5068461679497895, -8.049205477894898, -46.13605351033661, 181.32674632352655,
    1379.0058299809375, -17362.439304595126, 74763.50954557075, -153253.224706505, 146069.42432111388];
::XBro.PROBIT_Q <- [-4.229953084833044, -18.34139827806061, 155.92417471435067, -473.76692313678984,
    885.3867956273516, -5622.899296548299, 29074.574190289055, -42454.28580171358];

::XBro.probit <- function( _p )
{
    local p = ::Math.minf(1.0 - this.PROBIT_CLIP, ::Math.maxf(this.PROBIT_CLIP, _p));
    local q = p - 0.5, r = q * q, num = 0.0, den = 0.0;
    for (local i = this.PROBIT_P.len() - 1; i >= 0; i--) num = num * r + this.PROBIT_P[i];
    for (local i = this.PROBIT_Q.len() - 1; i >= 0; i--) den = den * r + this.PROBIT_Q[i];
    return q * num / (den * r + 1.0);
};

// Round half away from zero on the float, then colour from the player's point of view.
::XBro.readout <- function( _relative, _ours )
{
    local change = ::Math.floor(this.abs(_relative) + 0.5).tointeger();
    if (_relative < 0.0) change = -change;
    return {percent = (change > 0 ? "+" : "") + change + "%",
        tone = change == 0 ? "neutral" : (change > 0) == _ours ? "good" : "bad"};
};

::XBro.sideSummary <- function( _side, _ours )
{
    local blank = {percent = "—", tone = "neutral"};
    local exact = blank, shown = blank;
    if (_side.sumP > 0.0)
    {
        // The exact figure is unbounded upward and floors at -100%, so one lucky hit
        // reads +186%. The live badge weights it by that side's own evidence, the same
        // n / (n + 10) the bar uses; the results screen keeps the exact figure.
        local relative = 100.0 * (_side.hits / _side.sumP - 1.0);
        exact = this.readout(relative, _ours);
        shown = this.readout(relative * (_side.n / (_side.n + 10.0)), _ours);
    }
    return {n = _side.n, hits = _side.hits, expected = _side.sumP,
        percent = shown.percent, tone = shown.tone,
        exactPercent = exact.percent, exactTone = exact.tone};
};

::XBro.summary <- function()
{
    local ours = this.sideSummary(this.Battle.ours, true), theirs = this.sideSummary(this.Battle.theirs, false);
    local n = ours.n + theirs.n, observed = ours.hits + theirs.n - theirs.hits;
    local lower = 0.0, upper = 0.0, below = 0.0, point = 0.0, total = 0.0;
    foreach (k, mass in this.Battle.mass)
    {
        total += mass;
        if (k < observed) below += mass;
        if (k <= observed) lower += mass;
        if (k >= observed) upper += mass;
        if (k == observed) point = mass;
    }
    // Inclusive tails count ties. Choose the boundary towards the median; a
    // common outcome whose percentile interval contains 50% stays neutral.
    lower /= total; upper /= total;
    local rarity = 50.0;
    // Single-precision summation can place an exact half just below the median.
    if (lower < 0.5 - 0.0000001) rarity = 100.0 * lower;
    else if (upper < 0.5 - 0.0000001) rarity = 100.0 * (1.0 - upper);
    // The bar reads the mid-p lower tail instead: everything strictly below the observed
    // count plus half of the count's own mass. The two sides sum to exactly one, so the
    // sign falls out of one number and a count sitting at the median is exactly neutral,
    // with none of the percentile axis's pinning at 50 followed by a jump of a whole bin.
    local midp = (below + 0.5 * point) / total;
    // Clipping p bounds the axis on its own: the approximation reaches 2.9996 sigma there,
    // so the marker stays strictly inside the track without a second clamp.
    local z = this.probit(midp);
    // Evidence weight n / (n + 10): half way at attack 10, always on the tail's side of
    // neutral, so one discrete jump in a young distribution moves the bar less. Emphasis
    // warms up separately, full at 10.
    local weight = n / (n + 10.0);
    local text = "Even";
    if (rarity != 50.0)
    {
        // Round group sizes up, allowing only float noise at integer boundaries.
        local tail = rarity < 50.0 ? lower : upper;
        local group = ::Math.max(1, ::Math.ceil(100.0 * tail - 0.0001).tointeger());
        text = (rarity < 50.0 ? "Bottom " : "Top ") + group + "% of outcomes at these odds";
    }
    return {n = n, rarity = rarity, midp = midp, z = z, weight = weight,
        marker = 50.0 + this.SIGMA_SCALE * z * weight,
        emphasis = 0.5 + 0.5 * ::Math.minf(n / 10.0, 1.0), text = text,
        swing = (ours.hits - ours.expected) - (theirs.hits - theirs.expected), ours = ours, theirs = theirs};
};
