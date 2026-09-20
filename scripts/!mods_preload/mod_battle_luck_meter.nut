::include("scripts/mods/battle_luck_meter/core");
::BattleLuckMeter.Hooks <- ::Hooks.register(::BattleLuckMeter.ID, ::BattleLuckMeter.Version, ::BattleLuckMeter.Name);
::BattleLuckMeter.Hooks.require("mod_msu >= 1.9.0", "mod_modern_hooks >= 0.6.0");
::BattleLuckMeter.Hooks.queue(">mod_msu", function() {
    ::BattleLuckMeter.Mod <- ::MSU.Class.Mod(::BattleLuckMeter.ID, ::BattleLuckMeter.Version, ::BattleLuckMeter.Name);
    foreach (file in ["stats", "capture", "ui"]) ::include("scripts/mods/battle_luck_meter/" + file);
    ::MSU.UI.JSConnection.battleLuckMeterLog <- ::BattleLuckMeter.uiReceipt;
    ::BattleLuckMeter.registerSettings();
    ::BattleLuckMeter.registerTooltips();
    ::Hooks.registerLateJS("ui/mods/battle_luck_meter/battle_luck_meter.js");
    ::Hooks.registerCSS("ui/mods/battle_luck_meter/battle_luck_meter.css");
    ::BattleLuckMeter.Hooks.hook("scripts/ui/screens/tactical/tactical_combat_result_screen", function(q) {
        q.queryData = @(__original) function() {
            local data = __original();
            try { data.battleLuckMeterLuck <- ::BattleLuckMeter.resultState("combatInformation" in data ? data.combatInformation : null); }
            catch (error) { ::BattleLuckMeter.fail("results", error); }
            return data;
        };
    });
    ::BattleLuckMeter.Hooks.hook("scripts/skills/skill", function(q) {
        q.attackEntity = @(__original) function( _user, _targetEntity, _allowDiversion = true ) {
            local trial = null;
            try { trial = ::BattleLuckMeter.price(this, _user, _targetEntity, _allowDiversion); }
            catch (error) { ::BattleLuckMeter.fail("capture", error); }
            local hit;
            try { hit = __original(_user, _targetEntity, _allowDiversion); }
            catch (error) { ::BattleLuckMeter.fail("native_attack", error); throw error; }
            try { ::BattleLuckMeter.settle(trial, hit); }
            catch (error) { ::BattleLuckMeter.fail("settle", error); }
            return hit;
        };
    });
    ::BattleLuckMeter.Hooks.hook("scripts/states/tactical_state", function(q) {
        q.onInit = @(__original) function() {
            try { ::BattleLuckMeter.begin(); }
            catch (error) { ::BattleLuckMeter.fail("reset", error); }
            return __original();
        };
        q.onFinish = @(__original) function() {
            try { ::BattleLuckMeter.log("close", {ended = ::BattleLuckMeter.Battle.ended}); }
            catch (error) { ::BattleLuckMeter.fail("close", error); }
            return __original();
        };
        q.onBattleEnded = @(__original) function() {
            try { ::BattleLuckMeter.finish(); }
            catch (error) { ::BattleLuckMeter.fail("summary", error); }
            return __original();
        };
    });
    ::BattleLuckMeter.Hooks.hook("scripts/ui/screens/tactical/modules/topbar/tactical_screen_topbar_round_information", function(q) {
        q.battleLuckMeterPush <- function( _data ) {
            if (this.isConnected()) this.m.JSHandle.asyncCall("battleLuckMeterUpdate", _data);
            else ::BattleLuckMeter.log("delivery", {push = _data.push, status = "disconnected"});
        };
        q.update = @(__original) function() {
            __original();
            try { ::BattleLuckMeter.push(); }
            catch (error) { ::BattleLuckMeter.fail("push", error); }
        };
    });
});
