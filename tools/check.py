"""Run behavioral checks; print full Squirrel output only on failure."""
from hashlib import sha256
from pathlib import Path
import re
import shutil
import subprocess
import sys
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent
MSU_SHA256 = '617af64bd4b354408b91f8b8618f94f664491edcd2cf4649b8ad52673c81b37b'
# The game runs Squirrel 3.0.4; sq30 is the release gate, sq (3.2) is the second opinion.
runners = [ROOT / '.tools/sq30', ROOT / '.tools/sq']
for runner in runners:
    if shutil.which(str(runner)) is None:
        sys.exit(f'Build the Squirrel runner at {runner.relative_to(ROOT)}; see docs/DEVELOPMENT.md.')
if shutil.which('node') is None:
    sys.exit('Install Node.js to run UI checks; see docs/DEVELOPMENT.md.')
msu_zip = ROOT / '.tools/mod_msu-1.9.0.zip'
if not msu_zip.is_file() or sha256(msu_zip.read_bytes()).hexdigest() != MSU_SHA256:
    sys.exit('Place the pinned mod_msu-1.9.0.zip in .tools/; see THIRD_PARTY.md.')

with ZipFile(msu_zip) as archive:
    for name in archive.namelist():
        if name.startswith('msu/') and name.endswith('.nut'):
            destination = ROOT / '.tools/msu-contract' / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(archive.read(name))

# Read-only instrument: the runtime must never read the combat log or roll dice itself.
runtime = [*ROOT.glob('scripts/mods/xbro/*.nut'), ROOT / 'scripts/!mods_preload/mod_xbro.nut']
for path in runtime:
    for forbidden in ('EventLog', 'logEx', 'Rolled', 'Math.rand'):
        if forbidden in path.read_text():
            sys.exit(f'{path.relative_to(ROOT)} references {forbidden}; xBro only reads attackEntity results.')

for runner in runners:
    for suite in ['tests/run.nut', 'tests/settings.nut']:
        result = subprocess.run([str(runner), suite], cwd=ROOT, text=True, capture_output=True)
        passed = re.search(r'^XBRO_TESTS_PASSED (\d+)$', result.stdout, re.MULTILINE)
        # Squirrel's CLI may return success after an exception.
        if result.returncode or result.stderr or passed is None:
            print(result.stdout, end='')
            print(result.stderr, end='', file=sys.stderr)
            sys.exit(1)
        print(f'{runner.name} {suite}: {passed[1]} passed', flush=True)

# The audit tool must rebuild every finished battle from the lines the mod actually writes.
sample = subprocess.run([str(runners[0]), 'tests/sample.nut'], cwd=ROOT, text=True, capture_output=True)
audit = subprocess.run([sys.executable, 'tools/audit.py', '-'], cwd=ROOT, input=sample.stdout, text=True, capture_output=True)
tampered = sample.stdout.replace('ours_hits=6', 'ours_hits=7', 1).replace('text="Even"', 'text="Lucky 65%"', 1)
assert tampered != sample.stdout
denied = subprocess.run([sys.executable, 'tools/audit.py', '-'], cwd=ROOT, input=tampered, text=True, capture_output=True)
if sample.returncode or sample.stderr or audit.returncode or '2 match, 1 unfinished, 0 mismatch' not in audit.stdout \
        or denied.returncode != 1 or '0 match, 1 unfinished, 2 mismatch' not in denied.stdout:
    print(sample.stdout + audit.stdout + denied.stdout, end='')
    print(sample.stderr + audit.stderr + denied.stderr, end='', file=sys.stderr)
    sys.exit(1)
print(f'tools/audit.py tests/sample.nut: {audit.stdout.splitlines()[-1]}; tampered end lines rejected', flush=True)

js_tests = sorted((ROOT / 'tests').glob('*.test.cjs'))
subprocess.run(['node', '--test', '--test-reporter=spec', *map(str, js_tests)], cwd=ROOT, check=True)
for path in sorted((ROOT / 'ui').rglob('*.js')):
    subprocess.run(['node', '--check', str(path)], check=True)
