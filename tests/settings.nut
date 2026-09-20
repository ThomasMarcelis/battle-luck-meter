// Preload under stubbed Modern Hooks with the real pinned MSU settings and tooltip classes.
try
{
    dofile("tests/fixtures.nut");
    ::MSU <- {Class = {}, System = {}, UI = {JSConnection = {}}, SystemID = {ModSettings = "ModSettings", Tooltips = "Tooltips"},
        requireTable = function( v ) { if (typeof v != "table") throw "Expected table"; },
        requireFunction = function( v ) { if (typeof v != "function") throw "Expected function"; },
        requireOneFromTypes = function( types, ... ) { foreach (v in vargv) if (types.find(typeof v) == null) throw "Unexpected type"; },
        requireBool = function( v ) { if (typeof v != "bool") throw "Expected boolean"; },
        requireString = function( ... ) { foreach (v in vargv) if (typeof v != "string") throw "Expected string"; },
        SemVer = {getTable = @(v) {Version = v, PreRelease = null, Metadata = null}}};
    foreach (file in ["classes/ordered_map", "systems/system", "systems/system_mod_addon", "systems/mod",
        "systems/mod_settings/settings_element", "systems/mod_settings/abstract_setting",
        "systems/mod_settings/elements/boolean_setting", "systems/mod_settings/elements/range_setting",
        "systems/mod_settings/settings_page", "systems/mod_settings/settings_panel",
        "systems/mod_settings/mod_settings_mod_addon", "systems/mod_settings/mod_settings_system",
        "systems/tooltips/abstract_tooltip", "systems/tooltips/tooltips/custom_tooltip",
        "systems/tooltips/tooltips_mod_addon", "systems/tooltips/tooltips_system"]) dofile(".tools/msu-contract/msu/" + file + ".nut");
    local disk = {}, writes = 0;
    local persistence = {hasFile = @(id) id in disk, readFile = @(id) disk[id], createFile = function( id, data ) { disk[id] <- data; writes++; }};
    ::MSU.Mod <- {PersistentData = persistence};
    foreach (id in ["Registry", "Debug", "Keybinds", "Serialization"]) ::MSU.System[id] <- {registerMod = function( mod ) {}};
    ::MSU.System.PersistentData <- {registerMod = function( mod ) { mod.PersistentData = persistence; }};
    ::MSU.System.Tooltips <- ::MSU.Class.TooltipsSystem();
    ::MSU.System.ModSettings <- ::MSU.Class.ModSettingsSystem();
    ::MSU.System.ModSettings.Screen = {updateSettingInJS = function( mod, id, value ) {}};
    ::getModSetting <- @(mod, id) ::MSU.System.ModSettings.getPanel(mod).getSetting(id);
    local hooks = {}, registration = null, queued = null, js = [], css = [], required = null;
    ::Hooks <- {
        register = function( id, version, name ) {
            registration = {id = id, version = version, name = name};
            return {require = function( ... ) { required = vargv; }, queue = function( order, fn ) { queued = fn; },
                hook = function( path, fn ) { hooks[path] <- fn; }};
        }, registerLateJS = function( path ) { js.push(path); }, registerCSS = function( path ) { css.push(path); }
    };
    ::include <- @(path) dofile(path + ".nut");
    dofile("scripts/!mods_preload/mod_xbro.nut");
    if (queued == null || ("summary" in ::XBro)) throw "Modules must load in the queued startup callback";
    queued.call(getroottable());
    local X = ::XBro, system = ::MSU.System.ModSettings;
    local count = 0;
    function test( name, fn ) { try { fn(); } catch (e) { throw name + ": " + e; } count++; print("PASS " + name + "\n"); }

    test("registration_requirements_and_ui_files", function() {
        check(X.ID == "mod_xbro", "technical ID remains compatible with existing settings and installs");
        check(X.Name == "Battle Luck Meter" && X.Version == "1.0.0", "public product identity");
        check(registration.id == X.ID && registration.version == X.Version && registration.name == X.Name, "registration identity");
        check(required.len() == 2 && required[0] == "mod_msu >= 1.9.0" && required[1] == "mod_modern_hooks >= 0.6.0", "requirements");
        check(js.len() == 1 && js[0] == "ui/mods/xbro/xbro.js" && css.len() == 1 && css[0] == "ui/mods/xbro/xbro.css", "ui registration");
        local receipt = "[xBroUI] schema=3 ui_seq=1 battle=0 event=ui";
        local seq = X.Sequence;
        ::MSU.UI.JSConnection.xbroLog(receipt);
        check(::Logs.top() == receipt && X.Sequence == seq, "MSU callback writes browser evidence without changing Squirrel sequence");
        foreach (path in ["scripts/skills/skill", "scripts/states/tactical_state",
            "scripts/ui/screens/tactical/modules/topbar/tactical_screen_topbar_round_information",
            "scripts/ui/screens/tactical/tactical_combat_result_screen"]) check(path in hooks, "hook missing: " + path);
    });

    test("settings_defaults_and_native_update", function() {
        local panel = system.getUIData()[X.ID];
        check(panel.name == X.Name && !panel.hidden && panel.pages.len() == 1, "settings page");
        local page = panel.pages[0].settings;
        check(page.len() == 2 && page[0].id == "Enabled" && page[1].id == "ShowPercentages", "visibility and percentages are configurable");
        local percentages = system.getPanel(X.ID).getSetting("ShowPercentages");
        check(percentages.getName() == "Show relative hit percentages"
            && percentages.getDescription().find("scaled by how many attacks") != null
            && percentages.getDescription().find("results screen shows them exactly") != null,
            "percentage setting describes the weighting it actually applies");
        check(X.enabled() == true && !X.showPercentages() && writes == 0, "percentages default off without disk writes");
        system.updateSettingsFromJS({[X.ID] = {Enabled = {type = "bool", value = false}}});
        check(!X.enabled() && writes == 1 && ::Errors.len() == 0, "visibility persists outside a battle");
        system.updateSettingsFromJS({[X.ID] = {Enabled = {type = "bool", value = true}}});
        world();
        local live = {pushed = [], isNull = @() false, xbroPush = function( _data ) { this.pushed.push(_data); }};
        ::Tactical.TopbarRoundInformation = live;
        system.updateSettingsFromJS({[X.ID] = {Enabled = {type = "bool", value = false}}});
        check(live.pushed.len() == 1 && live.pushed[0].enabled == false, "disabling mid-battle pushes the hidden state");
        system.updateSettingsFromJS({[X.ID] = {Enabled = {type = "bool", value = true}}});
        check(live.pushed.len() == 2 && live.pushed[1].enabled, "re-enabling pushes again");
        system.updateSettingsFromJS({[X.ID] = {ShowPercentages = {type = "bool", value = true}}});
        check(live.pushed.len() == 3 && live.pushed[2].show_percentages, "enabling percentages pushes the live state");
        system.updateSettingsFromJS({[X.ID] = {ShowPercentages = {type = "bool", value = false}}});
        check(live.pushed.len() == 4 && !live.pushed[3].show_percentages, "disabling percentages pushes the no-badge state");
    });

    test("old_minimum_setting_is_ignored_on_upgrade", function() {
        local previous = disk.ModSettings, oldWrites = writes;
        disk.ModSettings = {[X.ID] = {Enabled = true, MinAttacks = 30}};
        system.importPersistentSettings();
        check(X.enabled() && !X.showPercentages() && !system.getPanel(X.ID).hasSetting("MinAttacks"), "old gate is not registered and new option defaults off");
        X.reset(); X.record("ours", 0.95, false);
        check(X.state().ours_percent == "-9%" && near(X.state().marker, 47.030373, 0.0002), "old threshold cannot hide first attack");
        check(writes == oldWrites && disk.ModSettings[X.ID].MinAttacks == 30, "import leaves stored settings untouched");
        disk.ModSettings = previous; X.reset();
    });

    test("msu_tooltip_dispatch_is_dynamic", function() {
        local rows = ::MSU.System.Tooltips.getTooltip(X.ID, "Luck").getUIData({contentType = "msu-generic", modId = X.ID, elementId = "Luck"});
        check(rows.len() == 2 && rows[1].type == "header" && rows[1].text == "No attacks recorded", "empty tooltip");
        X.record("ours", 0.5, true);
        rows = ::MSU.System.Tooltips.getTooltip(X.ID, "Luck").getUIData({});
        check(rows.len() == 6 && rows[2].text == "You: 1/1 hits vs 0.50 expected", "tooltip reads live state");
        X.reset();
    });

    test("attack_hook_wraps_every_skill_call", function() {
        world();
        local calls = 0, weapon = skill(70);
        // The native body needs the skill as `this`; a wrong environment throws here.
        weapon.attackEntity <- function( _user, _target, _allowDiversion = true ) { calls++; return this.chance > 0 && _allowDiversion; };
        local q = {attackEntity = null};
        hooks["scripts/skills/skill"](q);
        weapon.attackEntity = q.attackEntity(weapon.attackEntity).bindenv(weapon);
        check(weapon.attackEntity(actor(1), actor(2)) == true && calls == 1, "default diversion argument passes through");
        check(weapon.attackEntity(actor(2), actor(1), false) == false && calls == 2, "explicit argument passes through");
        check(X.Battle.ours.n == 1 && X.Battle.ours.hits == 1 && X.Battle.theirs.n == 1 && X.Battle.theirs.hits == 0, "both sides recorded");
        check(weapon.priced == 2 && ::Errors.len() == 0, "priced via getHitchance without errors");
    });

    test("battle_lifecycle_resets_and_topbar_pushes", function() {
        world();
        X.record("ours", 0.5, true);
        local inits = 0, ends = 0, q = {onInit = null, onBattleEnded = null, onFinish = null};
        hooks["scripts/states/tactical_state"](q);
        local onInit = q.onInit(function() { inits++; check(X.Battle.ours.n == 0, "reset before native init"); return "ready"; });
        local battle = X.Battle.id;
        check(onInit() == "ready" && inits == 1, "native init runs and returns");
        check(X.Battle.id == battle + 1 && fields(::Logs.top()).event == "start", "init opens the next battle in the log");
        X.record("theirs", 0.5, true);
        local onEnd = q.onBattleEnded(function() { ends++; check(fields(::Logs.top()).event == "end", "summary before native end"); return "done"; });
        check(onEnd() == "done" && ends == 1 && fields(::Logs.top()).theirs_hits == "1", "native end runs after the summary line");
        ::logInfo = function( _text ) { throw "log.html on fire"; };
        check(onInit() == "ready" && onEnd() == "done" && inits == 2 && ends == 2, "native init and end survive a failing log");
        check(::Errors.len() == 2 && ::Errors[0].find("phase=\"log\"") != null && ::Errors[1].find("phase=\"log\"") != null, "failures reported");
        ::Errors.clear();
        ::logInfo = function( _text ) { ::Logs.push(_text); };

        local sent = [], updates = 0;
        local module = {m = {JSHandle = {asyncCall = function( _method, _data ) { sent.push([_method, _data]); }}}, connected = false,
            isConnected = function() { return this.connected; }, isNull = @() false, update = function() { updates++; }};
        local mq = {update = null};
        hooks["scripts/ui/screens/tactical/modules/topbar/tactical_screen_topbar_round_information"](mq);
        module.xbroPush <- mq.xbroPush.bindenv(module);
        module.update = mq.update(function() { updates++; }).bindenv(module);
        ::Tactical.TopbarRoundInformation = module;
        module.update();
        check(updates == 1 && sent.len() == 0, "disconnected module updates natively but pushes nothing");
        module.connected = true;
        module.update();
        check(updates == 2 && sent.len() == 1 && sent[0][0] == "xbroUpdate" && sent[0][1].theirs_percent == "—", "native update then push");
        X.begin();
        X.settle(X.price(skill(70), actor(1), actor(2), true), true);
        check(sent.len() == 2 && sent[1][1].ours_percent == "+4%" && ::Errors.len() == 0, "each recorded attack pushes the weighted live badge");
    });

    test("results_hook_preserves_native_data_for_every_outcome_and_failures", function() {
        X.finish();
        local q = {queryData = null}, calls = 0;
        hooks["scripts/ui/screens/tactical/tactical_combat_result_screen"](q);
        foreach (outcome in ["win", "loose", "retreat"])
        {
            local native = {combatInformation = outcome == "retreat" ? {result = outcome} : {result = outcome, title = "Native title", subTitle = "Native detail"},
                statistics = [1, 2, 3], stash = [], foundLoot = []};
            local screen = {data = native};
            screen.queryData <- q.queryData(function() { calls++; return this.data; }).bindenv(screen);
            local result = screen.queryData();
            check(result == native && result.combatInformation.result == outcome && result.statistics.len() == 3, "native result preserved");
            check(result.xbroLuck.ours_percent == "+43%", "luck added for " + outcome);
            if (outcome == "retreat") check(::Errors.top().find("native_outcome") != null && result.xbroLuck.ours_percent == "+43%", "a missing native slot cannot drop the payload");
            else check(fields(::Logs.top()).native_result == outcome, "native outcome journaled");
        }
        check(calls == 3, "native query called once per outcome");
        local resultState = X.resultState;
        X.resultState = function( _combatInformation = null ) { throw "missing results"; };
        local native = {statistics = []};
        check(q.queryData(function() { return native; })() == native, "mod failure preserves native payload");
        X.resultState = resultState;
        check(::Errors.top().find("missing results") != null, "failure logged");
    });

    print("XBRO_TESTS_PASSED " + count + "\n");
}
catch (e) { print("FAIL " + e + "\n"); }
