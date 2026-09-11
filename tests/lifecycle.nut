local X = ::XBro, cases = {};

function module( _connected, _isNull = false )
{
    return {pushed = [], connected = _connected, isNull = function() { return _isNull; },
        isConnected = function() { return this.connected; }, xbroPush = function( _data ) { this.pushed.push(_data); }};
}

cases.push_reaches_only_a_live_topbar_module <- function()
{
    settings();
    X.push();
    world();
    X.push();
    delete ::Tactical.TopbarRoundInformation;
    X.push();
    ::Tactical.TopbarRoundInformation <- module(true, true);
    X.push();
    check(::Tactical.TopbarRoundInformation.pushed.len() == 0, "dead weak reference pushed");
    local live = module(true);
    ::Tactical.TopbarRoundInformation = live;
    X.push();
    check(live.pushed.len() == 1 && live.pushed[0].pending && live.pushed[0].enabled && live.pushed[0].text == "", "initial pending state");
};

cases.state_carries_only_what_js_renders <- function()
{
    world(); settings({MinAttacks = 4, Enabled = false});
    feed("ours", [50, 50, 50, 50], [1, 1, 1, 1]);
    local state = X.state();
    check(!state.enabled && !state.pending && state.text == "Lucky 97%" && state.offset > 0.0, "state " + state.text);
    check(state.len() == 4, "state has exactly enabled, pending, offset, text");
};

cases.tooltip_reports_both_sides_and_the_verdict <- function()
{
    world(); settings();
    local rows = X.tooltip();
    check(rows.len() == 4 && rows[0].type == "title" && rows[0].text == "Luck", "title");
    check(rows[1].text == "You: 0/0 hit, 0.0 expected" && rows[2].text == "Enemy: 0/0 hit, 0.0 expected", "empty sides");
    check(rows[3].text == "Needs 8 attacks (0 so far)", "pending verdict: " + rows[3].text);
    feed("ours", [50, 50, 50, 50, 50, 50, 50, 50], [1, 1, 1, 1, 1, 1, 1, 0]);
    feed("theirs", [35, 6, 50], [0, 0, 1]);
    rows = X.tooltip();
    check(rows[1].text == "You: 7/8 hit, 4.0 expected" && rows[2].text == "Enemy: 1/3 hit, 0.9 expected", rows[1].text + " | " + rows[2].text);
    check(rows[3].text == "Luckier than 96% of battles", rows[3].text);
    X.reset();
    feed("theirs", [50, 50, 50, 50, 50, 50, 50, 50], [1, 1, 1, 1, 1, 1, 1, 0]);
    check(X.tooltip()[3].text == "Unluckier than 98% of battles", "unlucky verdict");
};

return cases;
