local X = ::BattleLuckMeter, cases = {};

function module( _connected, _isNull = false )
{
    return {pushed = [], connected = _connected, isNull = function() { return _isNull; },
        isConnected = function() { return this.connected; }, battleLuckMeterPush = function( _data ) { this.pushed.push(_data); }};
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
        && !live.pushed[0].show_percentages && live.pushed[0].ours_percent == "—" && live.pushed[0].theirs_percent == "—", "empty state");
};

cases.state_presents_immediate_values_even_when_hidden <- function()
{
    world(); settings({Enabled = false});
    X.record("ours", 0.5, true);
    local state = X.state();
    check(!state.enabled && !state.show_percentages && state.ours_percent == "+9%" && state.ours_tone == "good", "first hit presentation is weighted");
    check(near(state.marker, 51.02195, 0.0002) && near(state.emphasis, 0.55, 0.00001), "mid-p step and warm-up");
};

cases.tooltip_prioritises_rarity_and_keeps_detail_concise <- function()
{
    world(); settings();
    X.record("ours", 0.95, false);
    local rows = X.tooltip(), s = X.summary();
    check(rows.len() == 6 && rows[1].type == "header" && rows[1].text == s.text, "rarity is the tooltip header");
    check(rows[2].text == "You: 0/1 hits vs 0.95 expected", "precise expected hits");
    check(rows[3].text == "Enemy: 0/0 hits vs 0.00 expected", "empty side stays concise");
    check(rows[4].text == "Net: 0.95 hits against you." && rows[5].text == "Small sample: 1 attack counted.", "concise context");
    check(near(s.marker, 47.030373, 0.0002) && rows[1].text == "Bottom 5% of outcomes at these odds", "tooltip header is the exact tail, bar is weighted");
    feed("theirs", array(9, 50), array(9, 0));
    rows = X.tooltip();
    check(rows[3].text == "Enemy: 0/9 hits vs 4.50 expected" && rows[5].text == "10 attacks counted.", "misses end warm-up too");
};

cases.result_payload_uses_completed_battle_and_shows_the_exact_tail <- function()
{
    world(); local values = settings({ShowPercentages = true}); X.begin();
    check(X.resultState() == null, "no result from an unfinished battle");
    feed("ours", array(2, 50), array(2, 1));
    local live = X.state(); X.finish(); local data = X.resultState();
    check(data.enabled && data.show_percentages && data.ours_percent == "+100%" && data.theirs_percent == "—", "results readouts are exact, not weighted");
    check(live.ours_percent == "+17%" && live.ours_tone == "good", "the live badge for the same battle is weighted");
    check(near(live.marker, 53.195591, 0.0002) && near(live.emphasis, 0.6, 0.00001), "live bar is on the sigma axis and warming");
    check(data.marker == 75.0 && data.emphasis == 1.0 && data.text == "Top 25% of outcomes at these odds", "overview shows the raw tail at full emphasis");
    check(data.swing == "Net hit swing: 1.00 hits in your favour." && data.sample == "Small sample: 2 attacks.", "overview context without damping claims");
    check(data.text == X.tooltip()[1].text, "result and tooltip share undamped rarity");
    check(data.ours == "You: 2 hits vs 1.00 expected" && data.theirs == "Enemy: 0 hits vs 0.00 expected", "concise final hit totals");
    values.Enabled = false; check(!X.resultState().enabled, "disabled result");
    X.begin(); check(X.resultState() == null, "next battle clears availability");
    X.finish();
    check(X.resultState().ours_percent == "—" && X.resultState().theirs_percent == "—", "empty battle");
    check(X.resultState().marker == 50.0 && X.resultState().emphasis == 1.0, "empty overview is neutral at full emphasis");
    X.begin(); check(X.state().marker == 50.0 && X.state().emphasis == 0.5 && X.summary().weight == 0.0, "next battle restarts the weighting");
    X.finish();
    check(X.resultState().swing == "" && X.resultState().sample == "", "no fabricated context for empty battle");
    local emptyRows = X.tooltip();
    check(emptyRows.len() == 2 && emptyRows[1].text == X.resultState().text, "empty tooltip only reports the empty state");
    check(X.resultState().text == "No attacks recorded", "empty battle has no verdict");
    check(data.ours_percent == "+100%" && data.marker == 75.0, "old payload has no live references");
};

cases.net_swing_direction_and_rounded_zero_stay_consistent <- function()
{
    world(); settings();
    X.record("ours", 0.999, true);
    check(X.tooltip()[4].text == "Net: even.", "rounded positive zero is even");
    X.record("ours", 0.002, false);
    check(X.tooltip()[4].text == "Net: even.", "rounded negative zero is even");
    X.record("theirs", 0.5, false);
    check(X.tooltip()[4].text == "Net: 0.50 hits in your favour.", "enemy miss helps player");
    X.finish();
    check(X.resultState().swing == "Net hit swing: 0.50 hits in your favour.", "overview retains full direction wording");
};

return cases;
