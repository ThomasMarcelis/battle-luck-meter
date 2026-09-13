::include("scripts/mods/xbro/core");
::XBro.Hooks <- ::Hooks.register(::XBro.ID, ::XBro.Version, ::XBro.Name);
::XBro.Hooks.require("mod_msu >= 1.9.0", "mod_modern_hooks >= 0.6.0");
::XBro.Hooks.queue(">mod_msu", function() {
    ::XBro.Mod <- ::MSU.Class.Mod(::XBro.ID, ::XBro.Version, ::XBro.Name);
    foreach (file in ["stats", "capture", "ui"]) ::include("scripts/mods/xbro/" + file);
    ::MSU.UI.JSConnection.xbroLog <- ::XBro.uiReceipt;
    ::XBro.registerSettings();
    ::XBro.registerTooltips();
    ::Hooks.registerLateJS("ui/mods/xbro/xbro.js");
    ::Hooks.registerCSS("ui/mods/xbro/xbro.css");
    ::XBro.Hooks.hook("scripts/ui/screens/tactical/tactical_combat_result_screen", function(q) {
        q.queryData = @(__original) function() {
            local data = __original();
            try { data.xbroLuck <- ::XBro.resultState("combatInformation" in data ? data.combatInformation : null); }
            catch (error) { ::XBro.fail("results", error); }
            return data;
        };
    });
    ::XBro.Hooks.hook("scripts/skills/skill", function(q) {
        q.attackEntity = @(__original) function( _user, _targetEntity, _allowDiversion = true ) {
            local trial = null;
            try { trial = ::XBro.price(this, _user, _targetEntity, _allowDiversion); }
            catch (error) { ::XBro.fail("capture", error); }
            local hit;
            try { hit = __original(_user, _targetEntity, _allowDiversion); }
            catch (error) { ::XBro.fail("native_attack", error); throw error; }
            try { ::XBro.settle(trial, hit); }
            catch (error) { ::XBro.fail("settle", error); }
            return hit;
        };
    });
    ::XBro.Hooks.hook("scripts/states/tactical_state", function(q) {
        q.onInit = @(__original) function() {
            try { ::XBro.begin(); }
            catch (error) { ::XBro.fail("reset", error); }
            return __original();
        };
        q.onFinish = @(__original) function() {
            try { ::XBro.log("close", {ended = ::XBro.Battle.ended}); }
            catch (error) { ::XBro.fail("close", error); }
            return __original();
        };
        q.onBattleEnded = @(__original) function() {
            try { ::XBro.finish(); }
            catch (error) { ::XBro.fail("summary", error); }
            return __original();
        };
    });
    ::XBro.Hooks.hook("scripts/ui/screens/tactical/modules/topbar/tactical_screen_topbar_round_information", function(q) {
        q.xbroPush <- function( _data ) {
            if (this.isConnected()) this.m.JSHandle.asyncCall("xbroUpdate", _data);
            else ::XBro.log("delivery", {push = _data.push, status = "disconnected"});
        };
        q.update = @(__original) function() {
            __original();
            try { ::XBro.push(); }
            catch (error) { ::XBro.fail("push", error); }
        };
    });
});
