::XBro.registerSettings <- function()
{
    local page = this.Mod.ModSettings.addPage("General");
    local refresh = function( _old ) {
        try { ::XBro.log("settings", {enabled = ::XBro.enabled(), show_percentages = ::XBro.showPercentages()}); ::XBro.checkpoint("state"); ::XBro.push(); }
        catch (error) { ::XBro.fail("settings", error); }
    };
    page.addBooleanSetting("Enabled", true, "Show luck meter", "Show luck during battle and after the brother cards on the results screen.").addAfterChangeCallback(refresh);
    page.addBooleanSetting("ShowPercentages", false, "Show relative hit percentages",
        "Show raw relative hit percentages for you and the enemy. These raw percentages can swing sharply in small samples.").addAfterChangeCallback(refresh);
};

::XBro.registerTooltips <- function()
{
    this.Mod.Tooltips.setTooltips({Luck = ::MSU.Class.CustomTooltip(function( _data ) { return ::XBro.tooltip(); })});
};

::XBro.enabled <- @() this.Mod.ModSettings.getSetting("Enabled").getValue();
::XBro.showPercentages <- @() this.Mod.ModSettings.getSetting("ShowPercentages").getValue();

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
    return {enabled = this.enabled(), show_percentages = this.showPercentages(), marker = s.marker, emphasis = s.emphasis,
        ours_percent = s.ours.percent, ours_tone = s.ours.tone, theirs_percent = s.theirs.percent, theirs_tone = s.theirs.tone};
};

::XBro.sideText <- function( _label, _side )
{
    return _label + ": " + _side.hits + (_side.hits == 1 ? " hit vs " : " hits vs ")
        + ::format("%.2f", _side.expected) + " expected";
};

::XBro.sampleText <- function( _n )
{
    if (_n == 0) return "No attacks recorded.";
    return _n < 10 ? "Small sample: " + _n + (_n == 1 ? " attack." : " attacks.") : "Counted attacks: " + _n + ".";
};

::XBro.swingText <- function( _swing, _label = "Net hit swing" )
{
    local amount = ::format("%.2f", this.abs(_swing));
    if (amount == "0.00") return _label + ": even.";
    return _label + ": " + amount + " hits " + (_swing > 0 ? "in your favour." : "against you.");
};

::XBro.tooltipSideText <- function( _label, _side )
{
    return _label + ": " + _side.hits + "/" + _side.n + " hits vs " + ::format("%.2f", _side.expected) + " expected";
};

::XBro.tooltipSampleText <- function( _n )
{
    if (_n == 0) return "No attacks recorded.";
    if (_n < 10) return "Small sample: " + _n + (_n == 1 ? " attack counted." : " attacks counted.");
    return _n + " attacks counted.";
};

::XBro.logPush <- function( _data, _status, _combatInformation = null )
{
    local fields = clone _data;
    delete fields.battle;
    fields.attack <- this.Battle.ours.n + this.Battle.theirs.n;
    fields.status <- _status;
    // Journal the already-built native outcome without querying actors or changing UI
    // data. A missing slot is a diagnostic failure, never a lost payload.
    if (_combatInformation != null) try
    {
        fields.native_result <- _combatInformation.result;
        fields.native_title <- _combatInformation.title;
        fields.native_subtitle <- _combatInformation.subTitle;
    }
    catch (error) { this.fail("native_outcome", error); }
    this.log("push", fields);
};

// The capture boundary stops recording at battle end. No actor references or
// saved history enter JS. The overview shows the exact result, not the live weighting.
::XBro.resultState <- function( _combatInformation = null )
{
    if (!this.Battle.ended) return null;
    local data = this.state(), s = this.summary();
    data.marker = s.rarity; data.emphasis = 1.0;
    data.text <- s.n == 0 ? "No attacks recorded" : s.text;
    data.swing <- s.n == 0 ? "" : this.swingText(s.swing);
    data.sample <- s.n == 0 ? "" : this.sampleText(s.n);
    data.ours <- this.sideText("You", s.ours); data.theirs <- this.sideText("Enemy", s.theirs);
    data.battle <- this.Battle.id; data.push <- ++this.Pushes; data.surface <- "results";
    this.logPush(data, "requested", _combatInformation);
    return data;
};

::XBro.tooltip <- function()
{
    local s = this.summary();
    local ours = this.tooltipSideText("You", s.ours), theirs = this.tooltipSideText("Enemy", s.theirs);
    local swing = this.swingText(s.swing, "Net"), sample = this.tooltipSampleText(s.n);
    local rows = [
        {id = 1, type = "title", text = "Battle luck"},
        {id = 2, type = "header", text = s.n == 0 ? "No attacks recorded" : s.text}
    ];
    if (s.n != 0)
    {
        rows.push({id = 3, type = "text", text = ours});
        rows.push({id = 4, type = "text", text = theirs});
        rows.push({id = 5, type = "text", text = swing});
        rows.push({id = 6, type = "text", text = sample});
    }
    this.log("tooltip", {attack = s.n, ours = ours, theirs = theirs, verdict = rows[1].text, swing = swing, sample = sample});
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
