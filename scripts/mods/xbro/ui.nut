::XBro.registerSettings <- function()
{
    local page = this.Mod.ModSettings.addPage("General");
    local refresh = function( _old ) { ::XBro.push(); };
    page.addBooleanSetting("Enabled", true, "Show luck meter", "Show the luck bar under the round counter in battle.").addAfterChangeCallback(refresh);
    page.addRangeSetting("MinAttacks", 8, 4, 30, 1, "Minimum attacks", "Attacks before the meter shows a verdict.").addAfterChangeCallback(refresh);
};

::XBro.registerTooltips <- function()
{
    this.Mod.Tooltips.setTooltips({Luck = ::MSU.Class.CustomTooltip(function( _data ) { return ::XBro.tooltip(); })});
};

::XBro.enabled <- @() this.Mod.ModSettings.getSetting("Enabled").getValue();
::XBro.minAttacks <- @() this.Mod.ModSettings.getSetting("MinAttacks").getValue();

// Everything JS renders; JS never derives numbers itself.
::XBro.state <- function()
{
    local s = this.summary(this.minAttacks());
    return {enabled = this.enabled(), pending = s.pending, offset = s.offset, text = s.text};
};

::XBro.tooltip <- function()
{
    local min = this.minAttacks(), s = this.summary(min);
    local line = @(_label, _side) _label + ": " + _side.hits + "/" + _side.n + " hit, " + ::format("%.1f", _side.expected) + " expected";
    local verdict = s.pending ? "Needs " + min + " attacks (" + s.n + " so far)"
        : s.text == "Even" ? "Even" : (s.z > 0 ? "Luckier" : "Unluckier") + " than " + s.rank + "% of battles";
    return [
        {id = 1, type = "title", text = "Luck"},
        {id = 2, type = "text", text = line("You", s.ours)},
        {id = 3, type = "text", text = line("Enemy", s.theirs)},
        {id = 4, type = "text", text = verdict}
    ];
};

// Settings callbacks can fire outside a battle, before the topbar module ever existed.
::XBro.push <- function()
{
    if (!("Tactical" in getroottable()) || !("TopbarRoundInformation" in ::Tactical)) return;
    local module = ::Tactical.TopbarRoundInformation;
    if (module == null || module.isNull()) return;
    module.xbroPush(this.state());
};
