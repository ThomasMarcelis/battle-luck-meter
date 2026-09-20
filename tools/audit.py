"""Replay Battle Luck Meter evidence and verify capture, pricing, calculations and UI receipts.

usage: python3 tools/audit.py [--attacks] <log.html or - for stdin>
Exit 0: complete journal checks passed within the printed limits.
Exit 1: invalid/inconsistent evidence or a source-model pricing discrepancy.
Exit 2: incomplete evidence (including v0.2 arithmetic-only logs).
"""
from collections import namedtuple
import math
from statistics import NormalDist
import struct
from pathlib import Path
import sys

import re
import urllib.parse

# One entry, with its log.html time stamp when the row markup is present.
RUNTIME_CHANNEL = 'BattleLuckMeter'
UI_CHANNEL = 'BattleLuckMeterUI'
LINE = re.compile(r'(?:<div class="time">([^<]*)</div><div class="tag">[^<]*</div><div class="text">)?\['
                  + re.escape(RUNTIME_CHANNEL) + r'\] ([^<\n]*)')
FIELD = re.compile(r'([a-z_]+)=("[^"]*"|\S+)')
SIDES = ('ours', 'theirs')
TOLERANCE = 0.002  # the game sums 32-bit floats; three decimals can differ in the last digit


def parse(text):
    battles, warnings = {}, []
    for match in LINE.finditer(text):
        fields = {key: value.strip('"') for key, value in FIELD.findall(match.group(2))}
        fields['time'] = match.group(1) or ''
        battle = battles.setdefault(int(fields['battle']), {'start': None, 'attacks': [], 'end': None})
        if fields.get('event') == 'start':
            if battle['start'] is not None:
                warnings.append(f"battle {fields['battle']} starts twice: the file holds more than one game session; audit each session separately")
            battle['start'] = fields
        elif fields.get('event') == 'end':
            battle['end'] = fields
        elif 'attack' in fields:
            battle['attacks'].append(fields)
    return battles, warnings


def summary(attacks, min_attacks):
    """Normal approximation retained for schema-2 arithmetic logs."""
    sides = {side: {'n': 0, 'hits': 0, 'sumP': 0.0, 'sumPQ': 0.0} for side in SIDES}
    for attack in attacks:
        p, side = float(attack['p']), sides[attack['side']]
        side['n'] += 1
        side['hits'] += attack['hit'] == '1'
        side['sumP'] += p
        side['sumPQ'] += p * (1.0 - p)
    ours, theirs = sides['ours'], sides['theirs']
    variance = ours['sumPQ'] + theirs['sumPQ']
    diff = (ours['hits'] - ours['sumP']) - (theirs['hits'] - theirs['sumP'])
    z = diff / math.sqrt(variance) if variance > 0.0 else 0.0
    phi = 0.5 * (1.0 + math.erf(z / math.sqrt(2.0)))
    rank = min(99, math.floor(100.0 * max(phi, 1.0 - phi)))
    pending = ours['n'] + theirs['n'] < min_attacks
    text = '' if pending else 'Even' if -0.5 < z < 0.5 else ('Lucky ' if z > 0 else 'Unlucky ') + f'{rank}%'
    out = {'z': f'{z:.3f}', 'rank': str(rank), 'pending': str(int(pending)), 'text': text}
    for label, side in sides.items():
        out.update({f'{label}_n': str(side['n']), f'{label}_hits': str(side['hits']), f'{label}_expected': f"{side['sumP']:.3f}"})
    return out


def describe(fields):
    side = lambda label: f"{fields[label + '_hits']}/{fields[label + '_n']} hit, {fields[label + '_expected']} expected"
    return f"ours {side('ours')} | theirs {side('theirs')} | z={fields['z']} rank={fields['rank']} text=\"{fields['text']}\""


def compare(recomputed, written):
    mismatches = []
    for key in recomputed:
        if key not in written:
            mismatches.append(f'{key} missing from the end line')
        elif key.endswith('_expected') or key == 'z':
            if abs(float(recomputed[key]) - float(written[key])) > TOLERANCE:
                mismatches.append(f'{key} recomputed {recomputed[key]} but written {written[key]}')
        elif recomputed[key] != written[key]:
            mismatches.append(f'{key} recomputed {recomputed[key]} but written {written[key]}')
    return mismatches


def legacy_main(argv):
    show_attacks = '--attacks' in argv
    paths = [arg for arg in argv if arg != '--attacks']
    if len(paths) != 1:
        sys.exit(__doc__)
    text = sys.stdin.read() if paths[0] == '-' else Path(paths[0]).read_text(encoding='utf-8', errors='replace')
    battles, warnings = parse(text)
    if not battles:
        sys.exit('no Battle Luck Meter entries found')
    for warning in warnings:
        print(f'WARNING {warning}')
    counts = {'match': 0, 'unfinished': 0, 'mismatch': 0}
    for number, battle in sorted(battles.items()):
        attacks = battle['attacks']
        start = battle['start']
        header = f"started {start['time']}  version {start['version']}" if start else 'no start line'
        by_side = ', '.join(f"{side} {sum(a['side'] == side for a in attacks)}" for side in SIDES)
        print(f'battle {number}  ({header})  attacks {len(attacks)} ({by_side})')
        expected = [str(i) for i in range(1, len(attacks) + 1)]
        if [a['attack'] for a in attacks] != expected:
            print(f"  WARNING attack numbers are not 1..{len(attacks)}: some lines are missing or out of order")
        if show_attacks:
            for a in attacks:
                print(f"  #{a['attack']:>3} {a['side']:<6} {'hit ' if a['hit'] == '1' else 'miss'} chance={a['chance']:<5} p={a['p']}"
                      f"  {a['skill']} by \"{a['by']}\" on \"{a['on']}\"")
        end = battle['end']
        if end is None:
            counts['unfinished'] += 1
            print(f'  recomputed: {describe(summary(attacks, 8))}')
            print('  UNFINISHED: no end line (battle not over, or the game was quit); recomputed with min_attacks=8')
            continue
        recomputed = summary(attacks, int(end['min_attacks']))
        mismatches = compare(recomputed, end)
        print(f'  recomputed: {describe(recomputed)}')
        print(f'  mod wrote : {describe(end)}')
        if mismatches:
            counts['mismatch'] += 1
            for mismatch in mismatches:
                print(f'  MISMATCH {mismatch}')
        else:
            counts['match'] += 1
            print('  MATCH')
    print(f"{len(battles)} battles: {counts['match']} match, {counts['unfinished']} unfinished, {counts['mismatch']} mismatch")
    print('SCHEMA 2: pricing inputs, exclusions and UI receipts absent; arithmetic replay only')
    return 1 if counts['mismatch'] else 2


# Schemas 2 and 3 are journals, not just a collection of final totals. Every line and every
# attempted native call must reconcile, including errors and asynchronous UI reports.
CHANNELS = {
    RUNTIME_CHANNEL: 'runtime',
    UI_CHANNEL: 'ui',
}
JOURNAL_LINE = re.compile(r'\[(' + '|'.join(map(re.escape, CHANNELS)) + r')\] ([^<\n]*)')
TOKEN = re.compile(r'([a-z_]+)=("[^"\r\n]*"|[^\s"=]+)(?: +|$)')
BOOLS = {'enabled', 'show_percentages', 'pending', 'allow_diversion', 'target_present', 'alive', 'attackable', 'uses_hitchance',
         'able_to_die', 'ranged', 'projectile', 'by_controlled', 'on_controlled', 'hit', 'counted', 'ended', 'allied'}
REQUIRED = {
    'start': 'version model enabled min_attacks',
    'attempt': 'attempt round enabled min_attacks allow_diversion reason skill_id skill by_id by',
    'result': 'attempt hit result_type counted attack',
    'settings': 'enabled min_attacks',
    'state': 'attempts results excluded errors attack ours_n ours_hits ours_expected ours_variance theirs_n theirs_hits theirs_expected theirs_variance z rank offset pending enabled min_attacks text',
    'push': 'push attack status surface enabled pending offset text',
    'delivery': 'push status',
    'ui': 'origin_battle push view status surface',
    'tooltip': 'attack min_attacks ours theirs verdict',
    'error': 'phase detail',
    'close': 'ended',
}
REQUIRED['end'] = REQUIRED['state']

REQUIRED_V3 = dict(REQUIRED)
for event in ('start', 'attempt', 'settings'):
    REQUIRED_V3[event] = REQUIRED[event].replace(' min_attacks', '')
READOUT_FIELDS = ('marker', 'emphasis', 'ours_percent', 'ours_tone', 'theirs_percent', 'theirs_tone')
REQUIRED_V3.update(
    state='attempts results excluded errors attack ours_n ours_hits ours_expected ours_variance theirs_n theirs_hits theirs_expected theirs_variance rarity weight swing enabled text ' + ' '.join(READOUT_FIELDS),
    push='push attack status surface enabled ' + ' '.join(READOUT_FIELDS),
    tooltip='attack ours theirs verdict swing sample')
REQUIRED_V3['end'] = REQUIRED_V3['state']


def journal(text):
    entries, problems, schemas = [], [], set()
    for match in JOURNAL_LINE.finditer(text):
        raw, at, fields = match.group(2), 0, {}
        try:
            while at < len(raw):
                token = TOKEN.match(raw, at)
                if token is None:
                    raise ValueError(f'malformed field near {raw[at:at+40]!r}')
                key, value = token.group(1, 2)
                if key in fields:
                    raise ValueError(f'duplicate field {key}')
                if value.startswith('"'):
                    value = value[1:-1]
                    if re.search(r'%(?![0-9A-F]{2})', value):
                        raise ValueError('invalid percent escape')
                    value = urllib.parse.unquote(value, errors='strict')
                fields[key] = value
                at = token.end()
            channel = CHANNELS[match.group(1)]
            for key in ('schema', 'seq' if channel == 'runtime' else 'ui_seq', 'battle', 'event'):
                if key not in fields:
                    raise ValueError(f'missing {key}')
            schemas.add(fields['schema'])
            if fields['schema'] not in ('2', '3') or len(schemas) > 1:
                raise ValueError('unsupported or mixed schema')
            event = fields['event']
            if event not in REQUIRED:
                raise ValueError(f'unknown event {event}')
            for key in (REQUIRED_V3 if fields['schema'] == '3' else REQUIRED)[event].split():
                if key not in fields:
                    raise ValueError(f'{event}: missing {key}')
            for key in BOOLS & fields.keys():
                if fields[key] not in ('0', '1'):
                    raise ValueError(f'{key} must be 0 or 1')
            fields['channel'] = channel

            if channel == 'ui' and event != 'ui':
                raise ValueError('UI channel may only report presentation')
            if channel == 'runtime' and event == 'ui':
                raise ValueError('UI observations must come from the UI channel')
            entries.append(fields)
        except (ValueError, UnicodeError) as error:
            problems.append(f'line {len(entries)+1}: {error}')
    # Runtime/JS failures do not necessarily use the structured prefix.
    failure_line = re.compile(r'BattleLuckMeter [^<\r\n]*?failed[^<\r\n]*')
    for match in failure_line.finditer(text):
        problems.append('runtime error: ' + match.group(0))
    if sum(text.count(f'[{name}]') for name in CHANNELS) != len(list(JOURNAL_LINE.finditer(text))):
        problems.append('malformed Battle Luck Meter entry')
    return entries, problems


def number(e, key, integer=False):
    raw = e[key]
    if integer:
        if not re.fullmatch(r'-?\d+', raw):
            raise ValueError(f'{key} is not an integer: {raw}')
        return int(raw)
    value = float(raw)
    if not math.isfinite(value):
        raise ValueError(f'{key} is not finite')
    return value


PRICING_MODELS = {'displayed_chance_v1', 'displayed_chance_v2'}


def pricing(e, model='displayed_chance_v1'):
    """Derive eligibility and both probability interpretations from observed inputs.

    The reference probability assumes ordinary clamped attackEntity thresholds;
    it cannot see the native local threshold, reroll outcome or hidden mod changes.
    """
    flag = lambda k: number(e, k, True) == 1
    if not flag('enabled'):
        return 'disabled', None, None
    if not flag('target_present'):
        return 'null_target', None, None
    for key, reason in [('alive', 'dead_target'), ('attackable', 'unattackable_target'), ('uses_hitchance', 'no_hitchance')]:
        if not flag(key):
            return reason, None, None
    if not flag('able_to_die') and number(e, 'hp') == 1:
        return 'unkillable', None, None
    ours = number(e, 'by_faction', True) == number(e, 'player_faction', True)
    on_us = number(e, 'on_faction', True) == number(e, 'player_faction', True)
    if ours == on_us:
        return 'outside_sample', None, None
    if e['side'] != ('ours' if ours else 'theirs'):
        raise ValueError('side disagrees with factions')
    if flag('ranged'):
        if not flag('allow_diversion') and flag('projectile'):
            return 'diverted', None, None
        if flag('allow_diversion') and number(e, 'distance') > 1 and number(e, 'blockers', True) != 0:
            return 'blocked', None, None
    chance, reroll = number(e, 'chance'), number(e, 'reroll')
    if not 0 <= reroll <= 100:
        raise ValueError('reroll outside 0..100')
    if model not in PRICING_MODELS:
        raise ValueError('unsupported probability model')
    shift = 0
    if number(e, 'difficulty', True) == 0:
        shift = 5 if flag('by_controlled') else -5 if flag('on_controlled') else 0
    initial = min(1.0, max(0.0, (chance + shift) / 100.0))
    second = initial if model == 'displayed_chance_v1' else min(1.0, max(0.0, chance / 100.0))
    p = initial - initial * (reroll / 100.0) * (1.0 - second)
    for key, want in [('shift', shift), ('shifted', chance+shift), ('initial_p', initial), ('p', p)]:
        if abs(number(e, key)-want) > 0.000002:
            raise ValueError(f'{key}={e[key]}, derived {want:.9g}')
    # Enumerate integer faces offline, never in the game. Beginner shifts the
    # first die only; the native Lucky reroll compares an unshifted fresh die.
    first = sum((max(1, r-5) if shift == 5 else min(100, r+5) if shift == -5 else r) <= chance for r in range(1, 101))/100
    second = sum(r <= chance for r in range(1, 101))/100
    gate = math.floor(reroll)/100
    reference = first * (1-gate+gate*second)
    return 'counted', p, reference


def calculated(attacks, minimum):
    out = summary(attacks, minimum)
    variance = {}
    for side in SIDES:
        variance[side] = sum(float(a['p'])*(1-float(a['p'])) for a in attacks if a['side'] == side)
        out[side+'_variance'] = variance[side]
        out[side+'_expected'] = sum(float(a['p']) for a in attacks if a['side'] == side)
    delta = (int(out['ours_hits'])-out['ours_expected'])-(int(out['theirs_hits'])-out['theirs_expected'])
    total = sum(variance.values())
    z = delta/math.sqrt(total) if total else 0.0
    out.update(z=z, offset=0.0 if len(attacks)<minimum else math.tanh(z/2), attack=len(attacks))
    return out


def presentation(z, n, minimum):
    phi = 0.5*(1+math.erf(z/math.sqrt(2)))
    rank = min(99, math.floor(100*max(phi, 1-phi)))
    pending = n < minimum
    return {'rank': str(rank), 'pending': str(int(pending)),
            'offset': 0.0 if pending else math.tanh(z/2),
            'text': '' if pending else 'Even' if -0.5 < z < 0.5 else ('Lucky ' if z>0 else 'Unlucky ')+f'{rank}%'}


def float32(value):
    return struct.unpack('f', struct.pack('f', value))[0]


# A start line without marker_model is a 0.4.0/0.4.1 journal: linear warm-up that reached
# the raw tail at attack 10, results retaining that damping, and the old verdict/sample
# wording. 'evidence_weight_v1' is the 0.4.2-0.4.4 percentile axis; 'probit_evidence_weight_v1'
# is the 0.4.5+ standard-deviation axis reading the mid-p tail.
MARKER_MODELS = {None: 'linear', 'evidence_weight_v1': 'percentile', 'probit_evidence_weight_v1': 'probit'}
UI_MODELS = {None: 'always', 'bar_only_v1': 'never', 'relative_percent_option_v1': 'setting',
             'smoothed_percent_option_v1': 'setting'}
# Versions 0.4.5 and later weight the live badges; every earlier contract rendered the exact figure live.
Model = namedtuple('Model', 'legacy axis smoothed badges')
DEFAULT_MODEL = Model(False, 'percentile', False, 'always')
LEGACY_INTERPRETATION = ("Compared with battles with the same hit chances; equally lucky or unlucky outcomes count too. "
                         "Rarity uses the full calculation, before the bar's early damping.")

# The runtime's sigma axis: +-3 sigma spans the track, clipped at exactly Phi(-+3).
SIGMA_SCALE = float32(50/3)
PROBIT_CLIP = 0.0013498980316301035


def probit(p):
    """The true inverse normal CDF of the same clipped tail the runtime reads.

    Deliberately not the runtime's rational approximation: replaying that polynomial would
    only prove the same coefficients were written twice. Checking against the real quantile
    verifies the approximation itself, within the tolerance its accuracy earns.
    """
    return NormalDist().inv_cdf(min(float32(1-float32(PROBIT_CLIP)), max(float32(PROBIT_CLIP), float32(p))))


def badge(relative, side, weight=None):
    """Round half away from zero on the float, then colour from the player's point of view."""
    if relative is None:
        return '\u2014', 'neutral'
    if weight is not None:
        relative = float32(relative*weight)
    change = math.floor(float32(abs(relative)+0.5)) * (-1 if relative < 0 else 1)
    return ('0%' if change == 0 else f'{change:+d}%',
            'neutral' if not change else 'good' if (change > 0) == (side == 'ours') else 'bad')


def presentation_v3(s, model=DEFAULT_MODEL):
    n, rarity = int(s['attack']), float(s['rarity'])
    weight = min(n / 10, 1.0) if model.legacy else n / (n + 10)
    text = 'Even'
    if rarity != 50:
        group = max(1, math.ceil(min(rarity, 100-rarity)-0.0001))
        side = 'Bottom' if rarity < 50 else 'Top'
        text = (f'{side} {group}% {"unluckiest" if rarity < 50 else "luckiest"} battles' if model.legacy
                else f'{side} {group}% of outcomes at these odds')
    out = dict(weight=weight)
    if model.axis == 'probit':
        if 'midp' not in s:
            raise ValueError('missing midp')
        # Chain the bar from the runtime's own axis position where the journal carries one,
        # so a wrong axis and a wrong bar stay two findings, reported tail before geometry.
        out['z'] = derived = probit(float(s['midp']))
        z = float(s['z']) if 'z' in s else derived
        out['marker'] = float32(50+float32(float32(SIGMA_SCALE*z)*weight))
    else:
        out['marker'] = 50+(rarity-50)*weight
    out.update(emphasis=0.5+0.5*min(n / 10, 1.0), text=text)
    for side in SIDES:
        expected = float(s[side+'_expected'])
        relative = None
        if expected > 0:
            # Each runtime arithmetic operation rounds to a Squirrel float. The magnitude
            # keeps its fraction: journals whose engine Math.abs truncated it fail here.
            relative = float32(100*float32(float32(int(s[side+'_hits'])/float32(expected))-1))
        count = int(s[side+'_n'])
        live = float32(count/float32(count+10.0)) if model.smoothed else None
        out[side+'_percent'], out[side+'_tone'] = badge(relative, side, live)
        if model.smoothed:
            out[side+'_exact_percent'], out[side+'_exact_tone'] = badge(relative, side)
    return out


def calculated_v3(attacks, mass, model=DEFAULT_MODEL):
    out = {'attack': len(attacks)}
    for side in SIDES:
        sample = [a for a in attacks if a['side'] == side]
        # The journal's nine significant digits round-trip each priced float.
        # Replay the runtime's operations, including rounding after each sum;
        # a fixed per-attack tolerance cannot bound long-battle accumulation drift.
        expected, variance = 0.0, 0.0
        for attack in sample:
            p = float32(float(attack['p']))
            expected = float32(expected + p)
            variance = float32(variance + float32(p * float32(1-p)))
        out.update({side+'_n': len(sample), side+'_hits': sum(a['hit'] == '1' for a in sample),
                    side+'_expected': expected, side+'_variance': variance})
    observed = out['ours_hits'] + out['theirs_n'] - out['theirs_hits']
    total = math.fsum(mass)
    lower, upper = math.fsum(mass[:observed+1])/total, math.fsum(mass[observed:])/total
    out['rarity'] = 100*lower if lower < 0.5-1e-7 else 100*(1-upper) if upper < 0.5-1e-7 else 50.0
    if model.axis == 'probit':
        # Mid-p: everything strictly below the observed count plus half of its own mass.
        # The two sides sum to exactly one, so the bar's sign falls out of one number.
        out['midp'] = math.fsum(mass[:observed])/total + 0.5*(mass[observed]/total)
    out['swing'] = float32(float32(out['ours_hits']-out['ours_expected'])-float32(out['theirs_hits']-out['theirs_expected']))
    out.update(presentation_v3(out, model))
    return out


def verify_side_text_v3(e, s, compact=False):
    for side, label in [('ours', 'You'), ('theirs', 'Enemy')]:
        pattern = (rf'{label}: {s[side+"_hits"]} {"hit" if s[side+"_hits"] == 1 else "hits"} vs (\d+\.\d{{2}}) expected' if compact else
                   rf'{label}: {s[side+"_hits"]}/{s[side+"_n"]} hit, (\d+\.\d{{2}}) expected\. (.*)')
        match = re.fullmatch(pattern, e[side])
        if match is None or abs(float(match[1])-float(s[side+'_expected'])) > 0.00502:
            raise ValueError('displayed side counts or expected hits differ')
        if compact:
            continue
        percent = s[side+'_percent']
        explanation = 'No hit comparison yet.' if percent == '—' else 'About as many hits as expected.' if percent == '0%' else (
            f'{abs(int(percent[:-1]))}% {"more" if percent[0] == "+" else "fewer"} hits than expected.')
        if match[2] != explanation:
            raise ValueError('displayed hit comparison differs')


def verify_tooltip_side_text_v3(e, s, legacy=False):
    """The concise tooltip since 0.4.1; 0.4.0 journals carry the explained form."""
    if legacy:
        try:
            verify_side_text_v3(e, s)
            return
        except ValueError:
            pass
    for side, label in [('ours', 'You'), ('theirs', 'Enemy')]:
        match = re.fullmatch(
            rf'{label}: {s[side+"_hits"]}/{s[side+"_n"]} hits vs (\d+\.\d{{2}}) expected', e[side])
        if match is None or abs(float(match[1])-float(s[side+'_expected'])) > 0.00502:
            raise ValueError('displayed tooltip side counts or expected hits differ')


def sample_text(n, legacy=False):
    """Results overview sample line; legacy journals explained the damping they retained."""
    if n == 0:
        return 'No attacks recorded.'
    if n < 10:
        return f'Small sample: {n} {"attack" if n == 1 else "attacks"}.' + (
            ' Below 10 attacks, the bar stays closer to the centre.' if legacy else '')
    return f'Counted attacks: {n}.'


def tooltip_samples(n, legacy=False):
    concise = ('No attacks recorded.' if n == 0 else
               f'Small sample: {n} {"attack" if n == 1 else "attacks"} counted.' if n < 10 else f'{n} attacks counted.')
    return (concise, sample_text(n, True)) if legacy else (concise,)


def verify_swing_text(text, swing, label='Net hit swing'):
    if text == f'{label}: even.':
        if abs(swing) > 0.00502:
            raise ValueError('displayed net hit swing is not even')
        return
    match = re.fullmatch(rf'{label}: (\d+\.\d{{2}}) hits (in your favour|against you)\.', text)
    if (match is None or float(match[1]) == 0 or abs(float(match[1])-abs(swing)) > 0.00502
            or (match[2] == 'in your favour') != (swing > 0)):
        raise ValueError('displayed net hit swing differs')


def verify_tooltip_v3(e, s, legacy=False):
    n = int(s['attack'])
    verify_fields(e, {'attack': n, 'verdict': s['text'] if n else 'No attacks recorded'})
    # Legacy journals logged an unrendered interpretation sentence; the current tooltip has none.
    if legacy != ('interpretation' in e) or e.get('interpretation', LEGACY_INTERPRETATION) != LEGACY_INTERPRETATION:
        raise ValueError('tooltip interpretation disagrees with the journal model')
    # 0.4.0 labelled the swing like the overview; 0.4.1 introduced the concise label.
    verify_swing_text(e['swing'], float(s['swing']), 'Net hit swing' if legacy and e['swing'].startswith('Net hit swing:') else 'Net')
    if e['sample'] not in tooltip_samples(n, legacy):
        raise ValueError('displayed tooltip sample differs')
    verify_tooltip_side_text_v3(e, s, legacy)


# Derived geometry must match the runtime's own inputs almost exactly; accumulated sums
# drift with battle length. The axis tolerance is what the runtime's rational approximation
# of the inverse normal is worth: it stays within 8.6e-4 sigma of the true quantile in
# float32, so 0.002 sigma leaves a margin of two and is still only 0.03 bar points.
TIGHT_FIELDS = ('offset', 'marker', 'weight', 'emphasis')
PROBIT_TOLERANCE = 0.002


def verify_fields(e, expected):
    for key, want in expected.items():
        if key not in e:
            raise ValueError(f'missing {key}')
        if isinstance(want, float):
            # Single-precision accumulation in the game, double precision here.
            tolerance = (0.00002 if key in TIGHT_FIELDS else PROBIT_TOLERANCE if key == 'z'
                         else max(0.00002, int(expected.get('attack', 0))*0.000002))
            if abs(number(e, key)-want) > tolerance:
                raise ValueError(f'{key}: wrote {e[key]}, derived {want:.9g}')
        elif str(want) != e[key]:
            raise ValueError(f'{key}: wrote {e[key]!r}, derived {want!r}')


def verify_side_text(e, s):
    for key, side, label in [('ours', 'ours', 'You'), ('theirs', 'theirs', 'Enemy')]:
        prefix = f'{label}: {s[side+"_hits"]}/{s[side+"_n"]} hit, '
        if not e[key].startswith(prefix) or not e[key].endswith(' expected'):
            raise ValueError('displayed side counts differ')
        expected = float(e[key][len(prefix):-9])
        if not math.isfinite(expected) or abs(expected-s[side+'_expected']) > 0.05002:
            raise ValueError('displayed expected hits differ')


def audit_journal(text, show_attacks=False):
    entries, errors = journal(text)
    incomplete, models = [], []
    battles, pushes, receipts, views, destroyed = {}, {}, set(), set(), set()
    sequence = 0
    ui_sequence = 0
    last_render = {}
    for e in entries:
        try:
            if e['channel'] == 'runtime':
                seq = number(e, 'seq', True)
                if seq != sequence+1:
                    errors.append(f'journal sequence {sequence} -> {seq}: missing, duplicate or reordered entry')
                sequence = seq
            else:
                seq = number(e, 'ui_seq', True)
                if seq != ui_sequence+1:
                    errors.append(f'UI sequence {ui_sequence} -> {seq}: missing, duplicate or reordered receipt')
                ui_sequence = seq
            v3 = e['schema'] == '3'
            bid = number(e, 'battle', True)
            if bid < 0:
                raise ValueError('negative battle ID')
            b = battles.setdefault(bid, {'start': None, 'end': None, 'closed': False, 'attempts': {}, 'results': set(), 'attacks': [],
                                       'mass': [1.0], 'excluded': 0, 'enabled': None, 'minimum': None, 'states': 0, 'needs_state': False, 'needs_push': False,
                                       'presentation': None, 'model': DEFAULT_MODEL, 'pricing_model': 'displayed_chance_v1', 'show_percentages': None})
            event = e['event']
            if e['channel'] == 'runtime' and b['needs_push'] and event != 'push':
                errors.append(f'battle {bid}: missing push after state')
                b['needs_push'] = False
            if e['channel'] == 'runtime' and b['needs_state'] and event != 'state':
                errors.append(f'battle {bid}: missing state after counted result')
                b['needs_state'] = False
            if event == 'start':
                if b['start'] or b['attempts']:
                    raise ValueError('duplicate/late battle start')
                if e['model'] not in PRICING_MODELS:
                    raise ValueError('unsupported probability model')
                if e.get('marker_model') not in MARKER_MODELS:
                    raise ValueError('unsupported marker model')
                if e.get('ui_model') not in UI_MODELS:
                    raise ValueError('unsupported UI model')
                axis = MARKER_MODELS[e.get('marker_model')]
                b['model'] = Model(axis == 'linear', axis, e.get('ui_model') == 'smoothed_percent_option_v1',
                                   UI_MODELS[e.get('ui_model')])
                b['pricing_model'] = e['model']
                b['start'] = e
            if event in ('start', 'settings'):
                b['enabled'], b['minimum'] = e['enabled'], 10 if v3 else number(e, 'min_attacks', True)
                if v3 and b['model'].badges == 'setting':
                    if 'show_percentages' not in e:
                        raise ValueError(f'{event}: missing show_percentages')
                    b['show_percentages'] = e['show_percentages']
                if event == 'settings':
                    b['needs_state'] = True
                if not 4 <= b['minimum'] <= 30:
                    raise ValueError('minimum attacks outside settings range')
            if event == 'attempt':
                aid = number(e, 'attempt', True)
                if aid != len(b['attempts'])+1:
                    raise ValueError('nonconsecutive or duplicate attempt ID')
                b['attempts'][aid] = e
                if b['end']:
                    raise ValueError('attack attempted after end')
                if number(e, 'round', True) < 0:
                    raise ValueError('negative round')
                verify_fields(e, {'enabled': b['enabled']} if v3 else {'enabled': b['enabled'], 'min_attacks': b['minimum']})
                if e['reason'] == 'capture_error':
                    raise ValueError('capture failed')
                reason, p, reference = pricing(e, b['pricing_model'])
                if e['reason'] != reason:
                    raise ValueError(f'exclusion: wrote {e["reason"]}, derived {reason}')
                if e.get('target_present') == '1' and ('on_id' not in e or 'on' not in e):
                    raise ValueError('missing target identity')
                if p is not None:
                    if e.get('allied') == '1':
                        models.append(f'battle {bid} attempt {aid}: allied cross-faction attack included in opposing-side sample')
                    if not 0 <= number(e, 'p') <= 1:
                        raise ValueError('probability outside 0..1')
                    if abs(p-reference)>0.000002:
                        models.append(f'battle {bid} attempt {aid}: meter p={p:.6f}, integer-die reference p={reference:.6f}')
                if show_attacks:
                    print(f'battle {bid} attempt {aid} round {e["round"]}: {reason}, {e["skill"]} by {e["by"]!r} on {e.get("on", "null")!r}'
                          + (f' chance={e["chance"]} p={e["p"]}' if p is not None else ''))
            elif event == 'result':
                aid = number(e, 'attempt', True)
                if aid not in b['attempts'] or aid in b['results']:
                    raise ValueError('orphan or duplicate result')
                if b['end']:
                    raise ValueError('result after end')
                b['results'].add(aid)
                attempt = b['attempts'][aid]
                counted = attempt['reason'] == 'counted'
                verify_fields(e, {'result_type': 'bool', 'counted': int(counted)})
                if counted:
                    b['attacks'].append(dict(attempt, hit=e['hit']))
                    if v3:
                        q = float(attempt['p']) if attempt['side'] == 'ours' else 1-float(attempt['p'])
                        old = b['mass']
                        b['mass'] = [old[0]*(1-q)] + [old[k]*(1-q)+old[k-1]*q for k in range(1, len(old))] + [old[-1]*q]
                    b['needs_state'] = True
                else:
                    b['excluded'] += 1
                verify_fields(e, {'attack': len(b['attacks'])})
            elif event in ('state', 'end'):
                if event == 'end' and b['end']:
                    raise ValueError('duplicate end')
                minimum = 10 if v3 else number(e, 'min_attacks', True)
                if bid != 0:
                    verify_fields(e, {'enabled': b['enabled']} if v3 else {'enabled': b['enabled'], 'min_attacks': b['minimum']})
                if v3:
                    expected = calculated_v3(b['attacks'], b['mass'], b['model'])
                    # Raw arithmetic is verified independently below; readouts are formatted
                    # from the runtime's own float32 values so rounding ties keep their side.
                    displayed = presentation_v3(e, b['model'])
                    expected.update(displayed)
                    if b['model'].badges == 'setting':
                        expected['show_percentages'] = b['show_percentages']
                else:
                    expected = calculated(b['attacks'], minimum)
                    displayed = presentation(number(e, 'z'), len(b['attacks']), minimum)
                    # CDF approximation and 32-bit rounding can cross an integer rank
                    # boundary by less than 0.0001 percentage points. Accept that
                    # adjacent rank only at such a boundary, preserving strict text.
                    raw_rank = 100*max(0.5*(1+math.erf(number(e, 'z')/math.sqrt(2))), 0.5*(1-math.erf(number(e, 'z')/math.sqrt(2))))
                    written_rank = number(e, 'rank', True)
                    allowed_ranks = {max(50, min(99, math.floor(raw_rank+error))) for error in (-0.0001, 0.0001)}
                    if written_rank in allowed_ranks:
                        displayed['rank'] = str(written_rank)
                        if displayed['text'] not in ('', 'Even'):
                            displayed['text'] = ('Lucky ' if number(e, 'z')>0 else 'Unlucky ')+str(written_rank)+'%'
                    expected.update(displayed)
                expected.update(attempts=len(b['attempts']), results=len(b['results']), excluded=b['excluded'], errors=0)
                # Record the checkpoint before judging it, so one defective checkpoint is
                # one finding and later pushes are compared with the runtime's own values.
                b['presentation'] = displayed
                b['states'] += 1
                b['needs_state'] = False
                if event == 'state':
                    b['needs_push'] = True
                if event == 'end':
                    b['end'] = e
                verify_fields(e, expected)
                if event == 'end' and len(b['attempts']) != len(b['results']):
                    raise ValueError('battle ended with unsettled attempts')
            elif event == 'push':
                b['needs_push'] = False
                pid = number(e, 'push', True)
                if pid in pushes:
                    raise ValueError('duplicate push ID')
                pushes[pid] = dict(e, outside=(b['closed'] or bid == 0) and e['surface'] == 'battle')
                if e['surface'] not in ('battle', 'results'):
                    raise ValueError('unknown UI surface')
                if e['status'] not in ('requested', 'unavailable'):
                    raise ValueError('unknown delivery status')
                if bid != 0 and b['minimum'] is not None:
                    want = calculated_v3(b['attacks'], b['mass'], b['model']) if v3 else calculated(b['attacks'], b['minimum'])
                    if b['presentation'] is not None:
                        want.update(b['presentation'])
                    if e['surface'] == 'results':
                        if not b['end']:
                            raise ValueError('results payload before battle end')
                        if v3:
                            if not b['model'].legacy:
                                # The overview shows the raw tail at full emphasis.
                                want.update(marker=float(b['end']['rarity']), emphasis=1.0)
                            if b['model'].smoothed:
                                # Only the live surface is smoothed; the overview is exact.
                                for side in SIDES:
                                    want[side+'_percent'] = want[side+'_exact_percent']
                                    want[side+'_tone'] = want[side+'_exact_tone']
                            verify_side_text_v3(e, want, compact=True)
                            verify_fields(e, {'text': want['text'] if b['attacks'] else 'No attacks recorded',
                                              'sample': sample_text(len(b['attacks']), b['model'].legacy) if b['attacks'] else ''})
                            if b['attacks']:
                                verify_swing_text(e['swing'], float(want['swing']))
                            else:
                                verify_fields(e, {'swing': ''})
                        else:
                            want['text'] = 'No attacks recorded' if not b['attacks'] else 'Too few attacks' if want['pending']=='1' else want['text']
                            verify_side_text(e, want)
                    verify_fields(e, {k: want[k] for k in (('attack',) + READOUT_FIELDS if v3 else ('attack', 'pending', 'offset', 'text'))})
                    verify_fields(e, {'enabled': b['enabled']})
                    if v3 and b['model'].badges == 'setting':
                        verify_fields(e, {'show_percentages': b['show_percentages']})
            elif event == 'delivery':
                if number(e, 'push', True) not in pushes or e['status'] != 'disconnected':
                    raise ValueError('invalid delivery report')
                incomplete.append(f'battle {bid}: push {e["push"]} disconnected')
            elif event == 'ui':
                pid = number(e, 'push', True)
                if pid not in pushes:
                    raise ValueError('UI receipt without a push')
                push = pushes[pid]
                verify_fields(e, {'origin_battle': push['battle'], 'surface': push['surface']})
                if e['status'] == 'rendered':
                    if pid in receipts and push['surface'] == 'battle':
                        raise ValueError('duplicate render receipt')
                    if push['surface'] == 'results':
                        verify_fields(e, {'ours': push['ours'], 'theirs': push['theirs']})
                        if v3:
                            verify_fields(e, {k: push[k] for k in ('text', 'sample', 'swing')})
                    verify_fields(e, {'display': '' if push['enabled']=='1' else 'none'})
                    if v3:
                        readouts = tuple(k for k in READOUT_FIELDS if k not in ('marker', 'emphasis'))
                        if b['model'].badges == 'always':
                            verify_fields(e, {k: push[k] for k in readouts})
                            if 'badges' in e:
                                raise ValueError('legacy percentage UI receipt contains badge mode')
                        elif b['model'].badges == 'never' and any(k in e for k in readouts):
                            raise ValueError('bar-only UI receipt contains a percentage readout')
                        elif b['model'].badges == 'never' and 'badges' in e:
                            raise ValueError('bar-only UI receipt contains badge mode')
                        elif b['model'].badges == 'setting':
                            shown = push['enabled'] == '1' and push['show_percentages'] == '1'
                            verify_fields(e, {'badges': 'rendered' if shown else 'hidden'})
                            if shown:
                                verify_fields(e, {k: push[k] for k in readouts})
                            elif any(k in e for k in readouts):
                                raise ValueError('hidden badge receipt contains a percentage readout')
                        verify_fields(e, {'emphasis': float(push['emphasis'])})
                    else:
                        verify_fields(e, {'text': push['text'], 'pending': push['pending']})
                    left = e['left']
                    marker = float(push['marker']) if v3 else 50-float(push['offset'])*50
                    if not left.endswith('%') or not math.isfinite(float(left[:-1])) or abs(float(left[:-1])-marker)>0.002:
                        raise ValueError('rendered marker disagrees with pushed position')
                    if number(e, 'view', True) <= 0:
                        raise ValueError('invalid rendered view ID')
                    identity = (int(e['origin_battle']), number(e, 'view', True))
                    if identity in destroyed or pid <= last_render.get(identity, 0):
                        raise ValueError('render after destruction or out-of-order render')
                    last_render[identity] = pid
                    receipts.add(pid)
                    views.add(identity)
                elif e['status'] == 'suppressed':
                    if push['surface'] != 'results' or push['enabled'] != '0':
                        raise ValueError('unexpected suppressed result')
                    receipts.add(pid)
                elif e['status'] == 'destroyed':
                    identity = (int(e['origin_battle']), number(e, 'view', True))
                    if identity not in views or identity in destroyed or last_render.get(identity) != pid:
                        raise ValueError('orphan or duplicate view destruction')
                    destroyed.add(identity)
                else:
                    incomplete.append(f'battle {bid}: UI {e["status"]} for push {pid}')
            elif event == 'tooltip':
                if b['minimum'] is None:
                    continue
                if v3:
                    s = calculated_v3(b['attacks'], b['mass'], b['model'])
                    if b['presentation'] is not None:
                        s.update(b['presentation'])
                    verify_tooltip_v3(e, s, b['model'].legacy)
                else:
                    s = calculated(b['attacks'], b['minimum'])
                    if b['presentation'] is not None:
                        s.update(b['presentation'])
                    verdict = f'Needs {b["minimum"]} attacks ({len(b["attacks"])} so far)' if s['pending']=='1' else 'Even' if s['text']=='Even' else ('Luckier' if s['z']>0 else 'Unluckier')+f' than {s["rank"]}% of battles'
                    verify_fields(e, {'attack': len(b['attacks']), 'min_attacks': b['minimum'], 'verdict': verdict})
                    verify_side_text(e, s)
            elif event == 'error':
                raise ValueError(f'{e["phase"]}: {e["detail"]}')
            elif event == 'close':
                if b['closed']:
                    raise ValueError('duplicate screen close')
                b['closed'] = True
                if e['ended'] != str(int(b['end'] is not None)):
                    raise ValueError('close/end disagreement')
        except (KeyError, ValueError, TypeError, OverflowError) as error:
            errors.append(f'seq {e.get("seq", "?")} battle {e.get("battle", "?")} {e["event"]}: {error}')
    for bid, b in battles.items():
        if bid == 0:
            if b['attempts']:
                errors.append('attacks outside a numbered battle')
            continue
        if not b['start']:
            incomplete.append(f'battle {bid}: no start')
        if not b['end']:
            incomplete.append(f'battle {bid}: no end (partial or abandoned battle)')
        if not b['closed']:
            incomplete.append(f'battle {bid}: screen close not observed')
        if b['needs_push']:
            incomplete.append(f'battle {bid}: missing push after final state')
        if b['needs_state']:
            incomplete.append(f'battle {bid}: missing final state')
        if len(b['attempts']) != len(b['results']):
            incomplete.append(f'battle {bid}: unsettled attempts')
        own_pushes = [p for p in pushes.values() if int(p['battle'])==bid and not p['outside']]
        if b['closed']:
            for identity in views-destroyed:
                if identity[0] == bid:
                    incomplete.append(f'battle {bid}: view {identity[1]} destruction not observed')
        if not any(p['surface'] == 'battle' for p in own_pushes):
            incomplete.append(f'battle {bid}: no battle UI pushes')
        if b['end'] and b['closed'] and not any(p['surface'] == 'results' for p in own_pushes):
            incomplete.append(f'battle {bid}: no results payload observed')
        for p in own_pushes:
            if int(p['push']) not in receipts:
                incomplete.append(f'battle {bid}: no render receipt for push {p["push"]} ({p["status"]})')
        if b['minimum'] is not None:
            print(f'battle {bid}: {len(b["attempts"])} attempts, {len(b["results"])} results, {b["excluded"]} excluded, {b["states"]} checkpoints')
            if b['start'] and b['start']['schema'] == '3':
                s = calculated_v3(b['attacks'], b['mass'], b['model'])
                # Report what the finished battle showed: the exact per-side figures.
                shown = '_exact_percent' if b['model'].smoothed else '_percent'
                print(f'  You {s["ours"+shown]} | Enemy {s["theirs"+shown]} | {s["text"]} | rarity {s["rarity"]:.2f} | live marker {s["marker"]:.2f}')
            else:
                print('  '+describe(b['end'] if b['end'] else summary(b['attacks'], b['minimum'])))
    if not any(bid > 0 for bid in battles):
        incomplete.append('no numbered battle observed')
    for label, findings in [('ERROR', errors), ('MODEL DISCREPANCY', models), ('INCOMPLETE', incomplete)]:
        for finding in findings:
            print(f'{label}: {finding}')
    print(f'journal: {len(entries)} events, {len(errors)} errors, {len(models)} model discrepancies, {len(incomplete)} evidence gaps')
    print('LIMIT: reference pricing assumes ordinary clamped engine thresholds; native dice/hidden modifiers and attacks bypassing this hook are unobserved.')
    print('LIMIT: rarity is an inclusive tail of outcomes at the recorded odds, not a rank among battles (schema 2 uses a normal approximation); UI receipts confirm DOM assignment, not visible fit or a full install/removal lifecycle.')
    if not entries:
        return 1
    return 1 if errors or models else 2 if incomplete else 0


def main(argv):
    paths = [arg for arg in argv if arg != '--attacks']
    if len(paths) != 1:
        sys.exit(__doc__)
    text = sys.stdin.read() if paths[0] == '-' else Path(paths[0]).read_text(encoding='utf-8', errors='strict')
    if f'[{RUNTIME_CHANNEL}] schema=' not in text:
        if paths[0] == '-':
            from io import StringIO
            original, sys.stdin = sys.stdin, StringIO(text)
            try:
                return legacy_main(argv)
            finally:
                sys.stdin = original
        return legacy_main(argv)
    return audit_journal(text, '--attacks' in argv)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
