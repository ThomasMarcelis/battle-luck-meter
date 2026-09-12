::XBro.registerSettings <- function()
{
    local page = this.Mod.ModSettings.addPage("General");
    local refresh = function( _old ) {
        try { ::XBro.log("settings", {enabled = ::XBro.enabled()}); ::XBro.checkpoint("state"); ::XBro.push(); }
        catch (error) { ::XBro.fail("settings", error); }
    };
    page.addBooleanSetting("Enabled", true, "Show luck meter", "Show luck during battle and after the brother cards on the results screen.").addAfterChangeCallback(refresh);
};

::XBro.registerTooltips <- function()
{
    this.Mod.Tooltips.setTooltips({Luck = ::MSU.Class.CustomTooltip(function( _data ) { return ::XBro.tooltip(); })});
};

::XBro.enabled <- @() this.Mod.ModSettings.getSetting("Enabled").getValue();

// MSU's connection outlives tactical screens. Keep the browser's sequence and
// originating battle intact, including receipts arriving after a battle reset.
::XBro.uiReceipt <- function( _line )
{
    try
    {
        if (typeof _line != "string" || _line.find("[xBroUI] schema=3 ") != 0
            || _line.find("\n") != null || _line.find("\r") != null) throw "invalid UI receipt";
        ::logInfo(_line);
    }
    catch (error) { ::XBro.fail("ui_receipt", error); }
};

// Everything JS renders; JS never derives numbers itself.
::XBro.state <- function()
{
    local s = this.summary();
    return {enabled = this.enabled(), marker = s.marker, emphasis = s.emphasis,
        ours_percent = s.ours.percent, ours_tone = s.ours.tone, theirs_percent = s.theirs.percent, theirs_tone = s.theirs.tone};
};

::XBro.sideText <- function( _label, _side, _compact = false )
{
    if (_compact) return _label + ": " + _side.hits + (_side.hits == 1 ? " hit vs " : " hits vs ")
        + ::format("%.2f", _side.expected) + " expected";
    local text = _label + ": " + _side.hits + "/" + _side.n + " hit, " + ::format("%.2f", _side.expected) + " expected";
    if (_side.change == null) return text + ". No hit comparison yet.";
    if (_side.change == 0) return text + ". About as many hits as expected.";
    return text + ". " + ::Math.abs(_side.change) + "% " + (_side.change > 0 ? "more" : "fewer") + " hits than expected.";
};

// Use the same context on hover and in the final overview.
::XBro.sampleText <- function( _n )
{
    if (_n == 0) return "No attacks recorded.";
    return _n < 10 ? "Small sample: " + _n + (_n == 1 ? " attack." : " attacks.")
        + " Below 10 attacks, the bar stays closer to the centre." : "Counted attacks: " + _n + ".";
};

::XBro.swingText <- function( _swing )
{
    local amount = ::format("%.2f", ::Math.abs(_swing));
    if (amount == "0.00") return "Net hit swing: even.";
    return "Net hit swing: " + amount + " hits " + (_swing > 0 ? "in your favour." : "against you.");
};

::XBro.logPush <- function( _data, _status )
{
    local fields = clone _data;
    delete fields.battle;
    fields.attack <- this.Battle.ours.n + this.Battle.theirs.n;
    fields.status <- _status;
    this.log("push", fields);
};

// The capture boundary stops recording at battle end. No actor references or
// saved history enter JS; short battles retain exactly the live meter's damping.
::XBro.resultState <- function()
{
    if (!this.Battle.ended) return null;
    local data = this.state(), s = this.summary();
    data.text <- s.n == 0 ? "No attacks recorded" : s.text;
    data.swing <- s.n == 0 ? "" : this.swingText(s.swing);
    data.sample <- s.n == 0 ? "" : this.sampleText(s.n);
    data.ours <- this.sideText("You", s.ours, true); data.theirs <- this.sideText("Enemy", s.theirs, true);
    data.battle <- this.Battle.id; data.push <- ++this.Pushes; data.surface <- "results";
    this.logPush(data, "requested");
    return data;
};

::XBro.tooltip <- function()
{
    local s = this.summary();
    local swing = this.swingText(s.swing), sample = this.sampleText(s.n);
    local interpretation = "Compared with battles with the same hit chances; equally lucky or unlucky outcomes count too. Rarity uses the full calculation, before the bar's early damping.";
    local rows = [
        {id = 1, type = "title", text = "Battle luck"},
        {id = 2, type = "text", text = this.sideText("You", s.ours)},
        {id = 3, type = "text", text = this.sideText("Enemy", s.theirs)},
        {id = 4, type = "text", text = s.n == 0 ? "No attacks recorded" : s.text},
        {id = 5, type = "text", text = swing},
        {id = 6, type = "text", text = sample},
        {id = 7, type = "text", text = interpretation}
    ];
    this.log("tooltip", {attack = s.n, ours = rows[1].text, theirs = rows[2].text,
        verdict = rows[3].text, swing = swing, sample = sample, interpretation = interpretation});
    return rows;
};

// Settings callbacks can fire outside a battle, before the topbar module ever existed.
::XBro.push <- function()
{
    local data = this.state();
    data.battle <- this.Battle.id; data.push <- ++this.Pushes; data.surface <- "battle";
    local status = "unavailable", module = null;
    if (("Tactical" in getroottable()) && ("TopbarRoundInformation" in ::Tactical)) module = ::Tactical.TopbarRoundInformation;
    if (module != null && !module.isNull()) status = "requested";
    this.logPush(data, status);
    if (status == "requested") module.xbroPush(data);
};
