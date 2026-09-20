try
{
    dofile("tests/fixtures.nut");
    foreach (file in ["core", "stats", "capture", "ui"]) dofile("scripts/mods/battle_luck_meter/" + file + ".nut");
    loadfile("scripts/!mods_preload/mod_battle_luck_meter.nut");
    local count = 0;
    foreach (file in ["stats", "capture", "lifecycle", "logging"])
    {
        local cases = dofile("tests/" + file + ".nut"), names = [];
        foreach (name, test in cases) names.push(name);
        names.sort();
        foreach (name in names)
        {
            local globals = clone getroottable(), api = clone ::BattleLuckMeter, math = clone ::Math;
            ::Errors.clear();
            ::BattleLuckMeter.reset();
            ::Logs.clear();
            try { cases[name](); }
            catch (e) { throw file + "/" + name + ": " + e; }
            local added = [];
            foreach (key, value in getroottable()) if (!(key in globals)) added.push(key);
            foreach (key in added) delete getroottable()[key];
            foreach (key, value in globals) getroottable()[key] = value;
            ::BattleLuckMeter.clear(); foreach (key, value in api) ::BattleLuckMeter[key] <- value;
            ::Math.clear(); foreach (key, value in math) ::Math[key] <- value;
            count++;
            print("PASS " + file + "/" + name + "\n");
        }
    }
    print("BATTLE_LUCK_METER_TESTS_PASSED " + count + "\n");
    return 0;
}
catch (e)
{
    print("FAIL " + e + "\n");
    return 1;
}
