::XBro <- {
    ID = "mod_xbro", Name = "xBro", Version = "0.1.0",
    Battle = null
};

// One Poisson-binomial sample: n trials, observed hits, sum of p and of p(1-p).
::XBro.newSide <- @() {n = 0, hits = 0, sumP = 0.0, sumPQ = 0.0};

// "ours" = attacks by the player's faction; "theirs" = attacks against it.
::XBro.reset <- function()
{
    this.Battle = {ours = this.newSide(), theirs = this.newSide()};
};
::XBro.reset();
