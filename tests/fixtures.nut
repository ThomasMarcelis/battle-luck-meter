::Math <- {floor = floor, ceil = ceil, pow = pow, round = @(v) floor(v + 0.5), abs = @(v) v < 0 ? -v : v,
    max = @(a, b) a > b ? a : b, min = @(a, b) a < b ? a : b, maxf = @(a, b) a > b ? a : b, minf = @(a, b) a < b ? a : b,
    rand = function( ... ) { throw "Math.rand consumed by xBro"; }};
::Errors <- [];
::logError <- function( _text ) { ::Errors.push(_text); };
::Logs <- [];
::logInfo <- function( _text ) { ::Logs.push(_text); };

function check( _value, _message ) { if (!_value) throw _message; }
function near( _a, _b, _tolerance ) { return _a - _b < _tolerance && _b - _a < _tolerance; }

// key=value pairs of one log line; double-quoted values may contain spaces.
function fields( _line )
{
    local out = {}, re = regexp("([a-z_]+)=(\"[^\"]*\"|[^ ]+)"), at = 0;
    while (true)
    {
        local m = re.capture(_line, at);
        if (m == null) break;
        local value = _line.slice(m[2].begin, m[2].end);
        if (value[0] == '"') value = value.slice(1, value.len() - 1);
        out[_line.slice(m[1].begin, m[1].end)] <- value;
        at = m[0].end;
    }
    return out;
}

// Settings double: XBro reads Enabled/MinAttacks through Mod.ModSettings at use time.
function settings( _values = null )
{
    local values = {Enabled = true, MinAttacks = 8};
    if (_values != null) foreach (key, value in _values) values[key] = value;
    ::XBro.Mod <- {ModSettings = {getSetting = function( _id ) { local v = values[_id]; return {getValue = @() v}; }}};
    return values;
}

// Engine globals the capture path touches. Player faction is 1; blocked tiles and difficulty are injectable.
function world( _blocked = null, _difficulty = 1 )
{
    local blocked = _blocked == null ? [] : _blocked;
    ::Const <- {Faction = {Player = 1}, Tactical = {Common = {getBlockedTiles = function( _a, _b, _f ) { return blocked; }}}};
    ::World <- {Assets = {getCombatDifficulty = @() _difficulty}};
    ::Tactical <- {TopbarRoundInformation = null};
}

function tile( _distance ) { return {distance = _distance, getDistanceTo = function( _other ) { return this.distance; }}; }

function actor( _faction, _distance = 1 )
{
    return {faction = _faction, alive = true, attackable = true, ableToDie = true, hp = 50, tileRef = tile(_distance),
        name = _faction == 1 ? "Our Bro" : "Foe " + _faction, getName = function() { return this.name; },
        getFaction = function() { return this.faction; }, isAlive = function() { return this.alive; },
        isAttackable = function() { return this.attackable; }, isAbleToDie = function() { return this.ableToDie; },
        getHitpoints = function() { return this.hp; }, isPlayerControlled = function() { return this.faction == 1; },
        getTile = function() { return this.tileRef; }, reroll = 0,
        getCurrentProperties = function() { return {RerollDefenseChance = this.reroll}; }};
}

function skill( _chance, _ranged = false, _projectile = false )
{
    return {m = {IsShowingProjectile = _projectile}, chance = _chance, ranged = _ranged, hitchance = true, priced = 0,
        name = _ranged ? "Quick Shot" : "Slash", getName = function() { return this.name; }, isUsingHitchance = function() { return this.hitchance; }, isRanged = function() { return this.ranged; },
        getHitchance = function( _target ) { this.priced++; return this.chance; }};
}

// Feed one side a list of (chance, hit) pairs.
function feed( _side, _chances, _hits )
{
    foreach (i, chance in _chances) ::XBro.record(_side, chance / 100.0, _hits[i] == 1);
}
