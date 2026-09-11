::XBro <- {
    ID = "mod_xbro", Name = "xBro", Version = "0.2.0",
    Battles = 0, Battle = null
};

// One Poisson-binomial sample: n trials, observed hits, sum of p and of p(1-p).
::XBro.newSide <- @() {n = 0, hits = 0, sumP = 0.0, sumPQ = 0.0};

// Audit trail in Documents/Battle Brothers/log.html: one "[xBro] key=value ..." entry per event.
// The file is HTML, so entries must not contain angle brackets; strings with spaces are double-quoted.
::XBro.log <- @(_text) ::logInfo("[xBro] " + _text);

// "ours" = attacks by the player's faction; "theirs" = attacks against it.
::XBro.reset <- function()
{
    this.Battle = {id = this.Battles, ours = this.newSide(), theirs = this.newSide()};
};
::XBro.reset();

// Each tactical battle gets the next session-wide number so its lines can be told apart in the log.
::XBro.begin <- function()
{
    this.Battles++;
    this.reset();
    this.log("battle=" + this.Battle.id + " event=start version=" + this.Version);
};
