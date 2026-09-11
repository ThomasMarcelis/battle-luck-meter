try
{
    dofile("tests/fixtures.nut");
    foreach (file in ["core", "stats", "capture", "ui"]) dofile("scripts/mods/xbro/" + file + ".nut");
    loadfile("scripts/!mods_preload/mod_xbro.nut");
    local count = 0;
    foreach (file in ["stats", "capture", "lifecycle", "logging"])
    {
        local cases = dofile("tests/" + file + ".nut"), names = [];
        foreach (name, test in cases) names.push(name);
        names.sort();
        foreach (name in names)
        {
            local globals = clone getroottable(), api = clone ::XBro, math = clone ::Math;
            ::Errors.clear();
            ::XBro.reset();
            ::Logs.clear();
            try { cases[name](); }
            catch (e) { throw file + "/" + name + ": " + e; }
            local added = [];
            foreach (key, value in getroottable()) if (!(key in globals)) added.push(key);
            foreach (key in added) delete getroottable()[key];
            foreach (key, value in globals) getroottable()[key] = value;
            ::XBro.clear(); foreach (key, value in api) ::XBro[key] <- value;
            ::Math.clear(); foreach (key, value in math) ::Math[key] <- value;
            count++;
            print("PASS " + file + "/" + name + "\n");
        }
    }
    print("XBRO_TESTS_PASSED " + count + "\n");
    return 0;
}
catch (e)
{
    print("FAIL " + e + "\n");
    return 1;
}
