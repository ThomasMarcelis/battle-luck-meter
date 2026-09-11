::include("scripts/mods/xbro/core");
::XBro.Hooks <- ::Hooks.register(::XBro.ID, ::XBro.Version, ::XBro.Name);
::XBro.Hooks.require("mod_msu >= 1.9.0", "mod_modern_hooks >= 0.6.0");
::XBro.Hooks.queue(">mod_msu", function() {
    ::XBro.Mod <- ::MSU.Class.Mod(::XBro.ID, ::XBro.Version, ::XBro.Name);
    foreach (file in ["stats", "capture", "ui"]) ::include("scripts/mods/xbro/" + file);
    ::XBro.registerSettings();
    ::XBro.registerTooltips();
    ::Hooks.registerLateJS("ui/mods/xbro/xbro.js");
    ::Hooks.registerCSS("ui/mods/xbro/xbro.css");
    ::XBro.Hooks.hook("scripts/skills/skill", function(q) {
        q.attackEntity = @(__original) function( _user, _targetEntity, _allowDiversion = true ) {
            local trial = ::XBro.price(this, _user, _targetEntity, _allowDiversion);
            local hit = __original(_user, _targetEntity, _allowDiversion);
            if (trial != null) ::XBro.settle(trial, hit);
            return hit;
        };
    });
    ::XBro.Hooks.hook("scripts/states/tactical_state", function(q) {
        q.onInit = @(__original) function() {
            try { ::XBro.begin(); }
            catch (error) { ::logError(::XBro.Name + " reset failed: " + error); }
            return __original();
        };
        q.onBattleEnded = @(__original) function() {
            try { ::XBro.finish(); }
            catch (error) { ::logError(::XBro.Name + " summary failed: " + error); }
            return __original();
        };
    });
    ::XBro.Hooks.hook("scripts/ui/screens/tactical/modules/topbar/tactical_screen_topbar_round_information", function(q) {
        q.xbroPush <- function( _data ) {
            if (this.isConnected()) this.m.JSHandle.asyncCall("xbroUpdate", _data);
        };
        q.update = @(__original) function() {
            __original();
            try { ::XBro.push(); }
            catch (error) { ::logError(::XBro.Name + " push failed: " + error); }
        };
    });
});
