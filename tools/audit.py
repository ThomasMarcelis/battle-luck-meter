"""Recompute xBro battle summaries from the attack lines in log.html and compare with the end lines the mod wrote.

usage: python3 tools/audit.py [--attacks] <log.html or - for stdin>
Exit status 1 when any finished battle's recomputation disagrees with its end line.
"""
import math
from pathlib import Path
import sys

import re

# One entry, with its log.html time stamp when the row markup is present.
LINE = re.compile(r'(?:<div class="time">([^<]*)</div><div class="tag">[^<]*</div><div class="text">)?\[xBro\] ([^<\n]*)')
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
    """Same arithmetic as scripts/mods/xbro/stats.nut, formatted like the mod's end line."""
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


def main(argv):
    show_attacks = '--attacks' in argv
    paths = [arg for arg in argv if arg != '--attacks']
    if len(paths) != 1:
        sys.exit(__doc__)
    text = sys.stdin.read() if paths[0] == '-' else Path(paths[0]).read_text(encoding='utf-8', errors='replace')
    battles, warnings = parse(text)
    if not battles:
        sys.exit('no [xBro] entries found')
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
    return 1 if counts['mismatch'] else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
