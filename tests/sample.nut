// Print a scripted session as log.html rows, so tools/audit.py is checked against the mod's real line format.
dofile("tests/fixtures.nut");
foreach (file in ["core", "stats", "capture", "ui"]) dofile("scripts/mods/xbro/" + file + ".nut");
local X = ::XBro;

function row( _kind, _text )
{
    print("<div class=\"row " + _kind + "\"><div class=\"entry-container\"><div class=\"time\">12:00:00</div><div class=\"tag\">SQ</div><div class=\"text\">" + _text + "</div></div></div>");
}
function play( _chances, _hits, _ours )
{
    foreach (i, chance in _chances)
    {
        local user = actor(_ours ? 1 : 2), target = actor(_ours ? 2 : 1);
        X.settle(X.price(skill(chance, i % 3 == 0), user, target, true), _hits[i] == 1);
    }
}

local uiSequence = 0;
function receipt( data )
{
    local line = "[xBroUI] schema=3 ui_seq=" + (++uiSequence) + " battle=" + data.origin_battle + " event=ui";
    foreach (key, value in data)
    {
        local kind = typeof value;
        line += " " + key + "=" + (kind == "bool" ? (value ? "1" : "0") : kind == "integer" ? value.tostring() : X.quote(value));
    }
    X.uiReceipt(line);
}
function renderedReceipt( _data, _receipt )
{
    local shown = _data.enabled && _data.show_percentages;
    _receipt.badges <- shown ? "rendered" : "hidden";
    if (shown)
    {
        _receipt.ours_percent <- _data.ours_percent;
        _receipt.theirs_percent <- _data.theirs_percent;
        _receipt.ours_tone <- _data.ours_tone;
        _receipt.theirs_tone <- _data.theirs_tone;
    }
    receipt(_receipt);
}
world(); local values = settings();
// A synchronous presentation double exercises the same receipt format as JS.
::Tactical.TopbarRoundInformation = {
    last = null, isNull = @() false,
    xbroPush = function( data ) {
        this.last = data;
        renderedReceipt(data, {origin_battle = data.battle, push = data.push, view = data.battle, surface = "battle", status = "rendered",
            display = data.enabled ? "" : "none", emphasis = data.emphasis, left = data.marker + "%"});
    }
};
function closeBattle()
{
    local result = X.resultState();
    if (result.enabled)
    {
        renderedReceipt(result, {origin_battle = result.battle, push = result.push, view = 1000 + result.battle, surface = "results", status = "rendered",
            display = "", emphasis = result.emphasis, left = result.marker + "%",
            text = result.text, ours = result.ours, theirs = result.theirs, swing = result.swing, sample = result.sample});
        receipt({origin_battle = result.battle, push = result.push, view = 1000 + result.battle, surface = "results", status = "destroyed"});
    }
    else receipt({origin_battle = result.battle, push = result.push, view = 0, surface = "results", status = "suppressed"});
    local data = ::Tactical.TopbarRoundInformation.last;
    receipt({origin_battle = data.battle, push = data.push, view = data.battle, surface = "battle", status = "destroyed"});
    X.log("close", {ended = X.Battle.ended});
}
X.begin();
play([82, 82, 64, 64, 60, 60, 55, 55, 50, 50, 50, 50, 68], [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0], true);
play([35, 35, 50, 50, 50, 50, 55, 55, 60, 60, 60, 60, 55, 55], [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0], false);
X.tooltip(); X.finish();
local result = X.resultState();
for (local v = 100; v < 102; v++)
{
    renderedReceipt(result, {origin_battle = result.battle, push = result.push, view = v, surface = "results", status = "rendered",
        display = "", emphasis = result.emphasis, left = result.marker + "%",
        text = result.text, ours = result.ours, theirs = result.theirs, swing = result.swing, sample = result.sample});
    receipt({origin_battle = result.battle, push = result.push, view = v, surface = "results", status = "destroyed"});
}
closeBattle();
X.begin();
// Nested result order, duplicate display names, safe escaping, excluded calls,
// a disabled interval and a settings change all survive independent replay.
local outer = X.price(skill(70), actor(1), actor(2), true);
local a = actor(1); a.name = "A\" p=0 x=\"<>&%\n\\";
X.settle(X.price(skill(40), actor(2), a, true), false);
X.settle(outer, true);
X.settle(X.price(skill(60), actor(1), null, true), false);
values.Enabled = false;
X.log("settings", {enabled = X.enabled(), show_percentages = X.showPercentages()}); X.checkpoint("state"); X.push();
X.settle(X.price(skill(70), actor(1), actor(2), true), false);
values.Enabled = true;
X.log("settings", {enabled = X.enabled(), show_percentages = X.showPercentages()}); X.checkpoint("state"); X.push();
values.ShowPercentages = true;
X.log("settings", {enabled = X.enabled(), show_percentages = X.showPercentages()}); X.checkpoint("state"); X.push();
play([75, 65, 80, 70], [1, 1, 0, 1], true);
values.ShowPercentages = false;
X.log("settings", {enabled = X.enabled(), show_percentages = X.showPercentages()}); X.checkpoint("state"); X.push();
values.ShowPercentages = true;
X.log("settings", {enabled = X.enabled(), show_percentages = X.showPercentages()}); X.checkpoint("state"); X.push();
X.tooltip(); X.finish(); closeBattle();
values.ShowPercentages = false;
// Mixed outcomes and accumulating fractional expectations.
X.begin();
play([60, 60, 60, 60, 60, 60], [1, 1, 1, 0, 0, 0], true);
X.tooltip(); X.finish(); closeBattle();
X.begin();
local chances = [], hits = [];
for (local i = 0; i < 25; i++) { chances.push(20); hits.push(i < 6 ? 1 : 0); }
play(chances, hits, true);
X.tooltip(); X.finish(); closeBattle();
// Float32 relative percentage is exactly 87.5 even though logged expected hits
// read as 1.60000002 in a double-precision auditor: runtime must display +88%.
X.begin();
play([40, 40, 40, 40], [1, 1, 1, 0], true);
X.tooltip(); X.finish(); closeBattle();
// Empty and one-attack results retain neutral placeholders or immediate readouts.
X.begin(); X.push(); X.tooltip(); X.finish(); closeBattle();
X.begin(); play([95], [0], true); X.tooltip(); X.finish(); closeBattle();
// A fractional percentage (1/0.61 = +63.9%) that an integer abs would truncate to +63%.
X.begin(); play([61], [1], true); X.tooltip(); X.finish(); closeBattle();
// Settings outside a closed battle must not require an unavailable topbar receipt.
::Tactical.TopbarRoundInformation = null;
values.Enabled = false;
X.log("settings", {enabled = X.enabled(), show_percentages = X.showPercentages()}); X.checkpoint("state"); X.push();
foreach (line in ::Logs) row("info", line);
