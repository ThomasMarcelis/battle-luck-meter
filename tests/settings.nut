// Preload under stubbed Modern Hooks with the real pinned MSU settings and tooltip classes.
try
{
    dofile("tests/fixtures.nut");
    ::MSU <- {Class = {}, System = {}, SystemID = {ModSettings = "ModSettings", Tooltips = "Tooltips"},
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
        check(registration.id == "mod_xbro" && registration.version == X.Version && registration.name == X.Name, "registration identity");
        check(required.len() == 2 && required[0] == "mod_msu >= 1.9.0" && required[1] == "mod_modern_hooks >= 0.6.0", "requirements");
        check(js.len() == 1 && js[0] == "ui/mods/xbro/xbro.js" && css.len() == 1 && css[0] == "ui/mods/xbro/xbro.css", "ui registration");
        foreach (path in ["scripts/skills/skill", "scripts/states/tactical_state",
            "scripts/ui/screens/tactical/modules/topbar/tactical_screen_topbar_round_information"]) check(path in hooks, "hook missing: " + path);
        check(hooks.len() == 3, "exactly three hooks");
    });

    test("settings_defaults_and_native_update", function() {
        local panel = system.getUIData()[X.ID];
        check(panel.name == X.Name && !panel.hidden && panel.pages.len() == 1, "settings page");
        local page = panel.pages[0].settings;
        check(page.len() == 2 && page[0].id == "Enabled" && page[1].id == "MinAttacks", "two settings");
        check(page[1].min == 4 && page[1].max == 30 && page[1].step == 1, "range bounds");
        check(X.enabled() == true && X.minAttacks() == 8 && writes == 0, "defaults without disk writes");
        system.updateSettingsFromJS({[X.ID] = {MinAttacks = {type = "Range", value = 12}}});
        check(X.minAttacks() == 12 && writes == 1 && ::Errors.len() == 0, "range update applied and persisted outside a battle");
        world();
        local live = {pushed = [], isNull = @() false, xbroPush = function( _data ) { this.pushed.push(_data); }};
        ::Tactical.TopbarRoundInformation = live;
        system.updateSettingsFromJS({[X.ID] = {Enabled = {type = "bool", value = false}}});
        check(live.pushed.len() == 1 && live.pushed[0].enabled == false, "disabling mid-battle pushes the hidden state");
        system.updateSettingsFromJS({[X.ID] = {Enabled = {type = "bool", value = true}}});
        check(live.pushed.len() == 2 && live.pushed[1].enabled, "re-enabling pushes again");
    });

    test("msu_tooltip_dispatch_is_dynamic", function() {
        local rows = ::MSU.System.Tooltips.getTooltip(X.ID, "Luck").getUIData({contentType = "msu-generic", modId = X.ID, elementId = "Luck"});
        check(rows.len() == 4 && rows[0].text == "Luck" && rows[3].text == "Needs 12 attacks (0 so far)", "empty tooltip");
        X.record("ours", 0.5, true);
        check(::MSU.System.Tooltips.getTooltip(X.ID, "Luck").getUIData({})[1].text == "You: 1/1 hit, 0.5 expected", "tooltip reads live state");
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
        local inits = 0, ends = 0, q = {onInit = null, onBattleEnded = null};
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
        check(::Errors.len() == 2 && ::Errors[0].find("reset failed") != null && ::Errors[1].find("summary failed") != null, "failures reported");
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
        check(updates == 2 && sent.len() == 1 && sent[0][0] == "xbroUpdate" && sent[0][1].pending, "native update then push");
        X.settle(X.price(skill(70), actor(1), actor(2), true), true);
        check(sent.len() == 2 && sent[1][1].pending && ::Errors.len() == 0, "each recorded attack pushes");
    });

    print("XBRO_TESTS_PASSED " + count + "\n");
}
catch (e) { print("FAIL " + e + "\n"); }
