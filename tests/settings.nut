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
    local hooks = {}, legacy = [], legendsInstalled = false, registration = null, queued = null, queuedOrder = null, js = [], css = [], required = null;
    ::Hooks <- {
        hasMod = function( id ) { return legendsInstalled && id == "mod_legends"; },
        register = function( id, version, name ) {
            registration = {id = id, version = version, name = name};
            return {require = function( ... ) { required = vargv; }, queue = function( ... ) { queued = vargv.top(); queuedOrder = clone vargv; queuedOrder.pop(); },
                hook = function( path, fn ) { hooks[path] <- fn; }};
        }, registerLateJS = function( path ) { js.push(path); }, registerCSS = function( path ) { css.push(path); }
    };
    ::mods_hookBaseClass <- function( name, fn ) { legacy.push({name = name, hook = fn}); };
    ::include <- @(path) dofile(path + ".nut");
    dofile("scripts/!mods_preload/mod_battle_luck_meter.nut");
    if (queued == null || ("summary" in ::BattleLuckMeter)) throw "Modules must load in the queued startup callback";
    queued.call(getroottable());
    local X = ::BattleLuckMeter, system = ::MSU.System.ModSettings;
    local count = 0;
    function test( name, fn ) { try { fn(); } catch (e) { throw name + ": " + e; } count++; print("PASS " + name + "\n"); }

    test("registration_requirements_and_ui_files", function() {
        check(X.ID == "mod_battle_luck_meter", "technical ID uses the clean pre-release identity");
        check(X.Name == "Battle Luck Meter" && X.Version == "1.0.2", "public product identity");
        check(registration.id == X.ID && registration.version == X.Version && registration.name == X.Name, "registration identity");
        check(required.len() == 2 && required[0] == "mod_msu >= 1.9.0" && required[1] == "mod_modern_hooks >= 0.6.0", "requirements");
        check(js.len() == 1 && js[0] == "ui/mods/battle_luck_meter/battle_luck_meter.js" && css.len() == 1 && css[0] == "ui/mods/battle_luck_meter/battle_luck_meter.css", "ui registration");
        local receipt = "[BattleLuckMeterUI] schema=3 ui_seq=1 battle=0 event=ui";
        local seq = X.Sequence;
        ::MSU.UI.JSConnection.battleLuckMeterLog(receipt);
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
        local live = {pushed = [], isNull = @() false, battleLuckMeterPush = function( _data ) { this.pushed.push(_data); }};
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

    test("blocked_enemy_shot_counts_at_aimed_chance_when_diversion_hits_our_bro", function() {
        world([{}]); settings(); X.reset();
        local shooter = actor(2, 4), intended = actor(1), bystander = actor(1);
        local bow = skill(11, true, true), nativeCalls = 0;
        bow.attackEntity <- function( _user, _target, _allowDiversion = true ) {
            nativeCalls++;
            if (_allowDiversion) {
                check(this.attackEntity(_user, bystander, false), "diverted roll hit another bro");
                return false; // The aimed target was missed; the projectile still hit.
            }
            return true;
        };
        bow.attackEntity = X.wrapAttack(bow.attackEntity).bindenv(bow);
        check(!bow.attackEntity(shooter, intended), "native result stays the aimed-target miss");
        check(nativeCalls == 2 && bow.priced == 1, "one aimed price, two unchanged native calls");
        check(X.Battle.theirs.n == 1 && X.Battle.theirs.hits == 1 && near(X.Battle.theirs.sumP, 0.11, 1e-6),
            "one enemy hit priced at the original 11%, not the diverted target");
        check(X.Battle.attempts == 2 && X.Battle.results == 2 && X.Battle.excluded == 1 && ::Errors.len() == 0,
            "nested native call is evidence, not a second sample");
        check(X.Battle.shots.len() == 0, "shot frame is gone after the native call");
    });

    test("blocked_shot_counts_native_hit_or_miss_without_a_follow_up", function() {
        world([{}]); settings(); X.reset();
        local weapon = skill(11, true, true), calls = 0;
        weapon.attackEntity <- function( _user, _target, _allowDiversion = true ) {
            calls++;
            return calls == 1;
        };
        weapon.attackEntity = X.wrapAttack(weapon.attackEntity).bindenv(weapon);
        local shooter = actor(2, 4), bro = actor(1);
        check(weapon.attackEntity(shooter, bro), "first shot hits the aimed target");
        check(!weapon.attackEntity(shooter, bro), "second shot misses everyone");
        check(calls == 2 && weapon.priced == 2 && X.Battle.theirs.n == 2 && X.Battle.theirs.hits == 1
            && near(X.Battle.theirs.sumP, 0.22, 1e-6) && X.Battle.excluded == 0 && X.Battle.shots.len() == 0,
            "both obstructed outcomes are counted once at their aimed chance");
    });

    test("legends_replaces_base_attack_on_each_inheritance_without_losing_capture", function() {
        world(); settings(); X.reset();
        check(queuedOrder.find(">mod_msu") != null && queuedOrder.find(">mod_legends") != null,
            "register compatibility hook after Legends' legacy hook when installed");
        check(legacy.len() == 0, "vanilla install does not add a legacy hook");
        legendsInstalled = true;
        X.registerCaptureHook();
        check(legacy.len() == 1 && legacy[0].name == "skills/skill", "Legends path uses its base-class hook point");
        local ancestor = skill(70), nativeCalls = 0;
        ancestor.m.ID <- "actives.test";
        local derived = {SuperName = "skill", skill = ancestor};
        foreach (hit in [true, false])
        {
            // Legends rewrites the ancestor each time another concrete skill inherits.
            ancestor.attackEntity <- function( _user, _target, _allowDiversion = true ) { nativeCalls++; return hit; };
            legacy[0].hook(derived);
            check(ancestor.attackEntity(actor(1), actor(2)) == hit, "native result is preserved");
        }
        check(nativeCalls == 2 && X.Battle.ours.n == 2 && X.Battle.ours.hits == 1,
            "each inherited skill reaches the final Legends body exactly once");
        check(X.Battle.attempts == 2 && X.Battle.results == 2 && ::Errors.len() == 0,
            "each attack gets exactly one attempt and result, not zero or duplicates");
        world([{}]); X.reset(); nativeCalls = 0; ancestor.priced = 0;
        ancestor.ranged = true; ancestor.m.IsShowingProjectile = true; ancestor.chance = 11;
        ancestor.attackEntity = function( _user, _target, _allowDiversion = true ) {
            nativeCalls++;
            if (_allowDiversion) { this.attackEntity(_user, actor(1), false); return false; }
            return true;
        };
        legacy[0].hook(derived);
        check(!ancestor.attackEntity(actor(2, 4), actor(1)), "Legends native aimed result stays a miss");
        check(nativeCalls == 2 && ancestor.priced == 1 && X.Battle.theirs.n == 1 && X.Battle.theirs.hits == 1
            && near(X.Battle.theirs.sumP, 0.11, 1e-6) && X.Battle.excluded == 1 && X.Battle.shots.len() == 0,
            "Legends replacement also credits the nested hit to the aimed 11% shot exactly once");
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
        module.battleLuckMeterPush <- mq.battleLuckMeterPush.bindenv(module);
        module.update = mq.update(function() { updates++; }).bindenv(module);
        ::Tactical.TopbarRoundInformation = module;
        module.update();
        check(updates == 1 && sent.len() == 0, "disconnected module updates natively but pushes nothing");
        module.connected = true;
        module.update();
        check(updates == 2 && sent.len() == 1 && sent[0][0] == "battleLuckMeterUpdate" && sent[0][1].theirs_percent == "—", "native update then push");
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
            check(result.battleLuckMeterLuck.ours_percent == "+43%", "luck added for " + outcome);
            if (outcome == "retreat") check(::Errors.top().find("native_outcome") != null && result.battleLuckMeterLuck.ours_percent == "+43%", "a missing native slot cannot drop the payload");
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

    print("BATTLE_LUCK_METER_TESTS_PASSED " + count + "\n");
}
catch (e) { print("FAIL " + e + "\n"); }
