::XBro.record <- function( _side, _p, _hit )
{
    local side = this.Battle[_side];
    side.n++;
    if (_hit) side.hits++;
    side.sumP += _p;
    side.sumPQ += _p * (1.0 - _p);
};

// The game's Math table has pow but no exp or sqrt.
::XBro.exp <- @(_x) ::Math.pow(2.718281828459045, _x);

// Standard normal CDF via Abramowitz-Stegun 7.1.26 (|error| < 1.5e-7).
::XBro.normalCdf <- function( _z )
{
    local x = (_z < 0 ? -_z : _z) / 1.4142135623730951;
    local t = 1.0 / (1.0 + 0.3275911 * x);
    local poly = t * (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
    local erf = 1.0 - poly * this.exp(-x * x);
    return 0.5 * (1.0 + (_z < 0 ? -erf : erf));
};

::XBro.tanh <- function( _x )
{
    if (_x > 10.0) return 1.0;
    if (_x < -10.0) return -1.0;
    local e = this.exp(2.0 * _x);
    return (e - 1.0) / (e + 1.0);
};

// Net luck: z of (our hits - expected) - (their hits - expected); independent sides add variance.
::XBro.summary <- function( _minAttacks )
{
    local ours = this.Battle.ours, theirs = this.Battle.theirs;
    local n = ours.n + theirs.n;
    local variance = ours.sumPQ + theirs.sumPQ;
    local diff = (ours.hits - ours.sumP) - (theirs.hits - theirs.sumP);
    local z = variance > 0.0 ? diff / ::Math.pow(variance, 0.5) : 0.0;
    local percentile = this.normalCdf(z);
    local rank = ::Math.floor(100.0 * (percentile >= 0.5 ? percentile : 1.0 - percentile)).tointeger();
    if (rank > 99) rank = 99;
    local pending = n < _minAttacks;
    local text = "";
    if (!pending) text = (z > -0.5 && z < 0.5) ? "Even" : (z > 0 ? "Lucky " : "Unlucky ") + rank + "%";
    return {
        n = n, pending = pending, z = z, rank = rank, text = text,
        offset = pending ? 0.0 : this.tanh(z / 2.0),
        ours = {n = ours.n, hits = ours.hits, expected = ours.sumP},
        theirs = {n = theirs.n, hits = theirs.hits, expected = theirs.sumP}
    };
};
