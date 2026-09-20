::XBro <- {
    ID = "mod_xbro", Name = "Battle Luck Meter", Version = "1.0.0",
    Battles = 0, Battle = null, Sequence = 0, Pushes = 0
};

::XBro.newSide <- @() {n = 0, hits = 0, sumP = 0.0, sumPQ = 0.0};

// The engine binds Math.abs, Math.min and Math.max to integer functions (see the
// start-line probes), so any float magnitude must be taken here instead.
::XBro.abs <- @( _value ) _value < 0 ? -_value : _value;

// Strings remain readable and single-line in log.html. Percent escapes are decoded
// exactly once by the auditor, after fields have been parsed (including UTF-8 bytes).
::XBro.quote <- function( _value )
{
    local out = "\"";
    foreach (c in _value.tostring())
    {
        if (c < 32 || c >= 127 || c == '%' || c == '"' || c == '\\' || c == '<' || c == '>' || c == '&')
            out += ::format("%%%02X", c & 255);
        else out += c.tochar();
    }
    return out + "\"";
};

// A session sequence covers Squirrel events; JS receipts have their own sequence.
// Increment before writing so a lost line leaves a detectable gap.
::XBro.log <- function( _event, _fields = null )
{
    this.Sequence++;
    try
    {
        local line = "[xBro] schema=3 seq=" + this.Sequence + " battle=" + this.Battle.id + " event=" + _event;
        if (_fields != null) foreach (key, value in _fields)
        {
            local kind = typeof value;
            line += " " + key + "=" + (kind == "bool" ? (value ? "1" : "0")
                : kind == "float" ? ::format("%.9g", value) : kind == "integer" ? value.tostring() : this.quote(value));
        }
        ::logInfo(line);
    }
    catch (error)
    {
        this.Battle.errors++;
        try { ::logError("[xBro] schema=3 seq=" + this.Sequence + " battle=" + this.Battle.id
            + " event=error phase=\"log\" detail=" + this.quote(error)); }
        catch (ignored) {}
    }
};

::XBro.fail <- function( _phase, _error )
{
    this.Battle.errors++;
    this.log("error", {phase = _phase, detail = _error.tostring()});
    try { ::logError("xBro " + _phase + " failed: " + _error); }
    catch (ignored) {}
};

::XBro.reset <- function()
{
    this.Battle = {id = this.Battles, ours = this.newSide(), theirs = this.newSide(),
        mass = [1.0], attempts = 0, results = 0, excluded = 0, errors = 0, ended = false};
};
::XBro.reset();

::XBro.begin <- function()
{
    this.Battles++;
    this.reset();
    this.log("start", {version = this.Version, model = "displayed_chance_v2",
        stats_model = "favorable_poisson_binomial_v1", marker_model = "probit_evidence_weight_v1", ui_model = "smoothed_percent_option_v1",
        ui_transport = "msu_connection_v1", enabled = this.enabled(), show_percentages = this.showPercentages(),
        // Constant-only probes distinguish engine math bindings from local test doubles.
        probe_abs = ::Math.abs(-1.75), probe_min = ::Math.min(95, 74.5), probe_max = ::Math.max(5, 74.5)});
};
