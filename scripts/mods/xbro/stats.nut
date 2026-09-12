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

::XBro.sideSummary <- function( _side, _ours )
{
    local percent = "—", tone = "neutral", change = null;
    if (_side.sumP > 0.0)
    {
        local relative = 100.0 * (_side.hits / _side.sumP - 1.0);
        change = ::Math.floor(::Math.abs(relative) + 0.5).tointeger();
        if (relative < 0.0) change = -change;
        percent = (change > 0 ? "+" : "") + change + "%";
        if (change != 0) tone = (change > 0) == _ours ? "good" : "bad";
    }
    return {n = _side.n, hits = _side.hits, expected = _side.sumP,
        change = change, percent = percent, tone = tone};
};

::XBro.summary <- function()
{
    local ours = this.sideSummary(this.Battle.ours, true), theirs = this.sideSummary(this.Battle.theirs, false);
    local n = ours.n + theirs.n, observed = ours.hits + theirs.n - theirs.hits;
    local lower = 0.0, upper = 0.0, total = 0.0;
    foreach (k, mass in this.Battle.mass)
    {
        total += mass;
        if (k <= observed) lower += mass;
        if (k >= observed) upper += mass;
    }
    // Inclusive tails count ties. Choose the boundary towards the median; a
    // common outcome whose percentile interval contains 50% stays neutral.
    lower /= total; upper /= total;
    local rarity = 50.0;
    // Single-precision summation can place an exact half just below the median.
    if (lower < 0.5 - 0.0000001) rarity = 100.0 * lower;
    else if (upper < 0.5 - 0.0000001) rarity = 100.0 * (1.0 - upper);
    local weight = ::Math.minf(n / 10.0, 1.0);
    local text = "Even";
    if (rarity != 50.0)
    {
        // Round group sizes up, allowing only float noise at integer boundaries.
        local tail = rarity < 50.0 ? lower : upper;
        local group = ::Math.max(1, ::Math.ceil(100.0 * tail - 0.0001).tointeger());
        text = (rarity < 50.0 ? "Bottom " : "Top ") + group + (rarity < 50.0 ? "% unluckiest battles" : "% luckiest battles");
    }
    return {n = n, rarity = rarity, weight = weight, marker = 50.0 + (rarity - 50.0) * weight,
        emphasis = 0.5 + 0.5 * weight, text = text,
        swing = (ours.hits - ours.expected) - (theirs.hits - theirs.expected), ours = ours, theirs = theirs};
};
