local X = ::XBro, cases = {};

function module( _connected, _isNull = false )
{
    return {pushed = [], connected = _connected, isNull = function() { return _isNull; },
        isConnected = function() { return this.connected; }, xbroPush = function( _data ) { this.pushed.push(_data); }};
}

cases.push_reaches_only_a_live_topbar_module <- function()
{
    settings(); X.push(); world(); X.push();
    delete ::Tactical.TopbarRoundInformation; X.push();
    ::Tactical.TopbarRoundInformation <- module(true, true); X.push();
    check(::Tactical.TopbarRoundInformation.pushed.len() == 0, "dead weak reference pushed");
    local live = module(true);
    ::Tactical.TopbarRoundInformation = live; X.push();
    check(live.pushed.len() == 1 && live.pushed[0].marker == 50.0 && live.pushed[0].enabled
        && live.pushed[0].ours_percent == "—" && live.pushed[0].theirs_percent == "—", "empty state");
};

cases.state_presents_immediate_values_even_when_hidden <- function()
{
    world(); settings({Enabled = false});
    X.record("ours", 0.5, true);
    local state = X.state();
    check(!state.enabled && state.ours_percent == "+100%" && state.ours_tone == "good", "first hit presentation");
    check(state.marker == 50.0 && near(state.emphasis, 0.55, 0.00001), "common outcome and warm-up");
};

cases.tooltip_explains_raw_rarity_and_both_hit_comparisons <- function()
{
    world(); settings();
    X.record("ours", 0.95, false);
    local rows = X.tooltip(), s = X.summary();
    check(rows[1].text == "You: 0/1 hit, 0.95 expected. 100% fewer hits than expected.", "precise early expected hits");
    check(rows[2].text.find("No hit comparison yet") != null, "undefined side");
    check(rows[3].text == s.text && near(s.marker, 45.5, 0.0001), "tooltip rarity is undamped");
    check(rows[4].text.find("0.95 hits against you") != null && rows[5].text.find("1 attack.") != null, "swing and counted sample");
    feed("theirs", array(9, 50), array(9, 0));
    rows = X.tooltip();
    check(rows[2].text.find("100% fewer") != null && rows[5].text == "Counted attacks: 10.", "misses end warm-up too");
};

cases.result_payload_uses_completed_battle_and_preserves_short_battle_damping <- function()
{
    world(); local values = settings(); X.begin();
    check(X.resultState() == null, "no result from an unfinished battle");
    feed("ours", array(2, 50), array(2, 1));
    local live = X.state(); X.finish(); local data = X.resultState();
    check(data.enabled && data.ours_percent == "+100%" && data.theirs_percent == "—", "short battle readouts");
    check(data.marker == live.marker && data.emphasis == live.emphasis && near(data.marker, 55.0, 0.0001), "same short-battle damping");
    check(data.swing == X.tooltip()[4].text && data.sample == X.tooltip()[5].text, "overview carries the same context");
    check(data.text == X.tooltip()[3].text, "result and tooltip share undamped rarity");
    check(data.ours == "You: 2 hits vs 1.00 expected" && data.theirs == "Enemy: 0 hits vs 0.00 expected", "concise final hit totals");
    values.Enabled = false; check(!X.resultState().enabled, "disabled result");
    X.begin(); check(X.resultState() == null, "next battle clears availability");
    X.finish();
    check(X.resultState().ours_percent == "—" && X.resultState().theirs_percent == "—", "empty battle");
    check(X.resultState().swing == "" && X.resultState().sample == "", "no fabricated context for empty battle");
    check(X.tooltip()[3].text == X.resultState().text, "empty tooltip does not call an unmeasured battle even");
    check(X.resultState().text == "No attacks recorded", "empty battle has no verdict");
    check(data.ours_percent == "+100%" && near(data.marker, 55.0, 0.0001), "old payload has no live references");
};

cases.net_swing_direction_and_rounded_zero_stay_consistent <- function()
{
    world(); settings();
    X.record("ours", 0.999, true);
    check(X.tooltip()[4].text == "Net hit swing: even.", "rounded positive zero is even");
    X.record("ours", 0.002, false);
    check(X.tooltip()[4].text == "Net hit swing: even.", "rounded negative zero is even");
    X.record("theirs", 0.5, false);
    check(X.tooltip()[4].text.find("0.50 hits in your favour") != null, "enemy miss helps player");
    X.finish();
    check(X.resultState().swing == X.tooltip()[4].text, "overview shares direction");
};

return cases;
