local X = ::XBro, cases = {};

cases.native_outcome_and_math_bindings_are_logged_without_changing_payloads <- function()
{
    world(); settings(); X.begin();
    local start = fields(::Logs.top());
    check(start.probe_abs == "1" && start.probe_min == "74" && start.probe_max == "74", "integer engine bindings are journaled");
    check(start.version == X.Version && start.model == "displayed_chance_v2" && start.marker_model == "probit_evidence_weight_v1"
        && start.ui_model == "smoothed_percent_option_v1" && start.show_percentages == "0", "start identifies the live UI contracts and default");
    X.finish();
    local native = {result = "win", title = "Victory", subTitle = "The enemy was destroyed in 4 rounds"};
    local payload = X.resultState(native), entry = fields(::Logs.top());
    check(entry.native_result == native.result && entry.native_title == native.title
        && entry.native_subtitle == native.subTitle, "native outcome retained verbatim");
    check(native.len() == 3 && !("native_result" in payload), "source and displayed payload preserved");
};

function events( _event )
{
    local out = [];
    foreach (line in ::Logs)
    {
        local e = fields(line);
        if (e.event == _event) out.push(e);
    }
    return out;
}

cases.all_attempts_have_a_reason_and_result_including_disabled_and_excluded <- function()
{
    world(); local values = settings(); X.begin();
    local a = actor(1), b = actor(2), weapon = skill(70);
    local t = X.price(weapon, a, b, true);
    check(events("attempt").len() == 1 && events("result").len() == 0, "attempt persisted before native result");
    X.settle(t, true);
    X.settle(X.price(weapon, a, a, true), false);
    values.Enabled = false;
    X.settle(X.price(weapon, a, b, true), false);
    local attempts = events("attempt"), results = events("result");
    check(attempts.len() == 3 && results.len() == 3 && attempts[1].reason == "outside_sample" && attempts[2].reason == "disabled", "every call has a reason");
    check(weapon.priced == 1 && X.Battle.ours.n == 1 && X.Battle.excluded == 2, "logging does not price excluded calls");
    check(results[0].counted == "1" && results[1].counted == "0" && results[2].attempt == "3", "results linked");
    check(attempts[0].by_id != attempts[0].on_id && attempts[0].skill_id == "actives.test" && attempts[0].round == "1", "stable IDs and round");
};

cases.pricing_inputs_retain_fractional_chance_difficulty_and_reroll <- function()
{
    world(null, 0); settings(); X.begin();
    local lucky = actor(1); lucky.reroll = 10;
    X.settle(X.price(skill(50.5), actor(2), lucky, true), true);
    local e = events("attempt")[0];
    check(e.chance == "50.5" && e.difficulty == "0" && e.shift == "-5" && e.by_controlled == "0" && e.on_controlled == "1", "pricing inputs");
    check(e.reroll == "10" && near(e.initial_p.tofloat(), 0.455, 1e-6) && near(e.p.tofloat(), 0.4324775, 1e-6), "unshifted Lucky reroll completely explained");
    local state = events("state")[0];
    check(near(state.theirs_variance.tofloat(), 0.4324775 * (1.0 - 0.4324775), 1e-6), "variance logged");
};

cases.alliance_evidence_does_not_change_the_current_sample <- function()
{
    world(); settings(); X.begin();
    local a = actor(1), ally = actor(3);
    a.isAlliedWith = @(_other) true;
    X.settle(X.price(skill(70), a, ally, true), true);
    check(events("attempt")[0].allied == "1" && X.Battle.ours.hits == 1, "alliance is observed without changing faction rule");
    a.isAlliedWith = function( _other ) { throw "alliance unavailable"; };
    X.settle(X.price(skill(70), a, ally, true), false);
    check(X.Battle.ours.n == 2 && events("error").top().phase == "alliance", "diagnostic failure preserves sampling");
};

cases.ui_receipts_preserve_origin_after_reset_and_failures_are_contained <- function()
{
    world(); settings(); X.begin();
    local line = "[xBroUI] schema=3 ui_seq=8 battle=" + X.Battle.id + " event=ui status=\"destroyed\"";
    X.begin(); local seq = X.Sequence;
    X.uiReceipt(line);
    check(::Logs.top() == line && X.Sequence == seq && X.Battle.ours.n == 0, "late receipt keeps its browser sequence and battle");
    X.uiReceipt(line + "\nforged line");
    check(events("error").top().phase == "ui_receipt", "multiline receipt rejected");
    ::logInfo = function( _text ) { throw "disk failed"; };
    X.uiReceipt(line);
    check(::Errors.len() > 0 && X.Battle.ours.n == 0, "journal failure cannot change combat state or escape callback");
};

cases.nested_calls_settle_in_native_return_order_and_stale_results_cannot_leak <- function()
{
    world(); settings(); X.begin();
    local outer = X.price(skill(70), actor(1), actor(2), true);
    local inner = X.price(skill(30), actor(2), actor(1), true);
    X.settle(inner, false); X.settle(outer, true);
    local r = events("result");
    check(r[0].attempt == "2" && r[1].attempt == "1" && r[1].attack == "2", "nested IDs preserve native order");
    local stale = X.price(skill(80), actor(1), actor(2), true);
    X.begin(); X.settle(stale, true);
    check(X.Battle.ours.n == 0 && events("error").top().phase == "settle", "stale result reported without changing new battle");
};

cases.logging_failure_and_ui_failure_never_suppress_native_sample <- function()
{
    world(); settings(); X.begin();
    local t = X.price(skill(70), actor(1), actor(2), true);
    ::logInfo = function( _text ) { throw "disk failed"; };
    X.settle(t, true);
    check(X.Battle.ours.n == 1 && X.Battle.errors > 0 && ::Errors.len() > 0, "failed disk still counts");
    ::logInfo = function( _text ) { ::Logs.push(_text); };
    X.push = function() { throw "UI failed"; };
    X.settle(X.price(skill(70), actor(1), actor(2), true), false);
    check(X.Battle.ours.n == 2 && events("result").top().hit == "0" && events("error").top().phase == "push", "UI failure still records and logs");
};

cases.names_are_escaped_without_affecting_the_attack <- function()
{
    world(); settings(); X.begin();
    local a = actor(1); a.name = "A\" p=0 x=\"<>&%\n\\";
    X.settle(X.price(skill(70), a, actor(2), true), true);
    local e = events("attempt")[0];
    check(e.by == "A%22 p=0 x=%22%3C%3E%26%25%0A%5C" && near(e.p.tofloat(), 0.7, 1e-6), "escaped names cannot inject fields or HTML");
    local b = actor(2); b.getName = function() { throw "unreadable name"; };
    X.settle(X.price(skill(70), actor(1), b, true), false);
    check(X.Battle.ours.n == 2 && events("error").top().phase == "identity", "missing decoration fails evidence, not the meter");
};

cases.end_contains_counters_and_duplicate_end_is_an_error <- function()
{
    world(); settings(); X.begin();
    X.settle(X.price(skill(50), actor(1), actor(2), true), true);
    X.finish();
    local e = events("end")[0];
    check(e.attempts == "1" && e.results == "1" && e.errors == "0" && e.ours_n == "1" && near(e.ours_variance.tofloat(), 0.25, 1e-6), "end counters and variance");
    X.finish();
    check(events("end").len() == 1 && events("error").top().phase == "finish", "duplicate lifecycle call surfaced");
};

return cases;
