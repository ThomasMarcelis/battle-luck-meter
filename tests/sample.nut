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

world(); settings();
row("info", "<span style=\"color: green;\">MSU registered <span style=\"color: white;\">xBro</span>, version: <span style=\"color: white;\">" + X.Version + "</span></span>");
// Battle 1: the owner's screenshot. 6/13 own hits against 7.9 expected; 8/14 enemy hits against 7.3.
X.begin();
play([82, 82, 64, 64, 60, 60, 55, 55, 50, 50, 50, 50, 68], [1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0], true);
play([35, 35, 50, 50, 50, 50, 55, 55, 60, 60, 60, 60, 55, 55], [1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0], false);
X.finish();
row("warning", "MSU Serialization: unrelated chatter between battles");
// Battle 2: quit to the menu after three attacks, so no end line.
X.begin();
play([70, 70], [1, 1], true);
play([40], [0], false);
// Battle 3: beginner difficulty, a Lucky brother, mixed sides, a verdict of Even.
world(null, 0); settings({MinAttacks = 6});
X.begin();
local lucky = actor(1); lucky.reroll = 10;
foreach (i, chance in [45, 60, 30, 55])
{
    X.settle(X.price(skill(chance), actor(3), lucky, true), i % 2 == 0);
}
play([75, 65, 80, 70], [1, 1, 0, 1], true);
X.finish();
foreach (line in ::Logs) row("info", line);
