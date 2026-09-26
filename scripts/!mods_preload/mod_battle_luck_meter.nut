::include("scripts/mods/battle_luck_meter/core");
::BattleLuckMeter.Hooks <- ::Hooks.register(::BattleLuckMeter.ID, ::BattleLuckMeter.Version, ::BattleLuckMeter.Name);
::BattleLuckMeter.Hooks.require("mod_msu >= 1.9.0", "mod_modern_hooks >= 0.6.0");
::BattleLuckMeter.wrapAttack <- function( _original ) {
    return function( _user, _targetEntity, _allowDiversion = true ) {
        local meter = ::BattleLuckMeter, parent = null, stack = meter.Battle.shots;
        // Native miss diversion calls this same skill with _allowDiversion=false.
        // Other re-entrant attacks still get their own sample.
        if (!_allowDiversion) for (local i = stack.len() - 1; i >= 0; i--)
            if (stack[i].skill == this && stack[i].user == _user && stack[i].trial != null)
            { parent = stack[i]; break; }
        local trial = null;
        try { trial = meter.price(this, _user, _targetEntity, _allowDiversion, parent); }
        catch (error) { ::BattleLuckMeter.fail("capture", error); }
        local frame = {skill = this, user = _user, trial = trial, hit = false};
        stack.push(frame);
        local hit;
        try { hit = _original.call(this, _user, _targetEntity, _allowDiversion); }
        catch (error) { stack.pop(); ::BattleLuckMeter.fail("native_attack", error); throw error; }
        stack.pop();
        frame.hit = frame.hit || hit == true;
        if (parent != null) parent.hit = parent.hit || frame.hit;
        try { meter.settle(trial, hit, frame.hit); }
        catch (error) { ::BattleLuckMeter.fail("settle", error); }
        return hit;
    };
};
::BattleLuckMeter.registerCaptureHook <- function() {
    if (::Hooks.hasMod("mod_legends"))
    {
        // Legends replaces the skill ancestor on each derived-class inheritance.
        // Register after its legacy callback and wrap the fresh body each time.
        ::mods_hookBaseClass("skills/skill", function(o) {
            while (!("m" in o && "ID" in o.m)) o = o[o.SuperName];
            o.attackEntity = ::BattleLuckMeter.wrapAttack(o.attackEntity);
        });
    }
    else this.Hooks.hook("scripts/skills/skill", function(q) {
        q.attackEntity = @(__original) ::BattleLuckMeter.wrapAttack(__original);
    });
};
::BattleLuckMeter.Hooks.queue(">mod_msu", ">mod_legends", function() {
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
    ::BattleLuckMeter.registerCaptureHook();
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
