"""Behavioral checks against a journal emitted by the real Squirrel runtime."""
import contextlib
import io
from pathlib import Path
import re
import subprocess
import sys
from tempfile import NamedTemporaryFile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import audit


class AuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        run = subprocess.run(['.tools/sq30', 'tests/sample.nut'], text=True, capture_output=True, check=True)
        if run.stderr or 'event=end' not in run.stdout:
            raise AssertionError(run.stderr or run.stdout)
        cls.text = run.stdout
        cls.lines = [(m.group(1),m.group(2)) for m in audit.JOURNAL_LINE.finditer(cls.text)]
        cls.lines = ['['+channel+'] '+fields for channel,fields in cls.lines]

    def replay(self, lines=None):
        text = self.text if lines is None else '\n'.join(lines)+'\n'
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = audit.audit_journal(text)
        return status, out.getvalue()

    def renumber(self, lines):
        seq = ui_seq = 0
        out = []
        for line in lines:
            if line.startswith('[xBroUI]'):
                ui_seq += 1
                line = re.sub(r'\bui_seq=\d+', f'ui_seq={ui_seq}', line)
            else:
                seq += 1
                line = re.sub(r'\bseq=\d+', f'seq={seq}', line)
            out.append(line)
        return out

    def change(self, event, key, value, surface=None):
        lines = self.lines.copy()
        index = next(i for i,s in enumerate(lines) if f'event={event} ' in s and (surface is None or f'surface="{surface}"' in s))
        lines[index], n = re.subn(rf'\b{key}=("[^"]*"|\S+)', f'{key}={value}', lines[index], count=1)
        self.assertEqual(n, 1)
        return lines

    def test_complete_nested_session_and_settings_replay(self):
        status, output = self.replay()
        self.assertEqual(status, 0, output)
        self.assertIn('0 errors, 0 model discrepancies, 0 evidence gaps', output)
        self.assertIn('battle 3:', output)
        self.assertIn('battle 4:', output)
        self.assertIn('You +88%', output)
        entries, errors = audit.journal(self.text)
        self.assertFalse(errors)
        self.assertTrue(any(e.get('on') == 'A" p=0 x="<>&%\n\\' for e in entries))

    def test_allied_cross_faction_attack_is_a_model_discrepancy(self):
        status, output = self.replay(self.change('attempt', 'allied', '1'))
        self.assertEqual(status, 1, output)
        self.assertIn('allied cross-faction attack included', output)
        self.assertIn('0 errors, 1 model discrepancies', output)

    def test_long_valid_battle_replays_float32_accumulation(self):
        script = Path('tests/sample.nut').read_text().replace(
            '// Settings outside a closed battle',
            'X.begin(); local longChances = array(300, 95), longHits = array(300, 1);\n'
            'for (local i = 0; i < 15; i++) longHits[i] = 0;\n'
            'play(longChances, longHits, true); X.tooltip(); X.finish(); closeBattle();\n'
            '// Settings outside a closed battle')
        with NamedTemporaryFile(mode='w', suffix='.nut', dir='.tools') as tmp:
            tmp.write(script); tmp.flush()
            run = subprocess.run(['.tools/sq30', tmp.name], text=True, capture_output=True, check=True)
        self.assertFalse(run.stderr)
        lines = ['['+m[1]+'] '+m[2] for m in audit.JOURNAL_LINE.finditer(run.stdout)]
        status, output = self.replay(lines)
        self.assertEqual(status, 0, output)
        self.assertIn('300 attempts, 300 results', output)
        self.assertIn('0 errors, 0 model discrepancies, 0 evidence gaps', output)

    def test_missing_duplicate_and_reordered_events_fail(self):
        cases = [self.lines[:1]+self.lines[2:], self.lines[:2]+self.lines[1:],
                 self.lines[:1]+[self.lines[2], self.lines[1]]+self.lines[3:]]
        for lines in cases:
            with self.subTest(lines=lines[:3]):
                status, output = self.replay(lines)
                self.assertEqual(status, 1, output)
                self.assertIn('sequence', output)

    def test_tampering_with_inputs_results_calculations_and_rendering_fails(self):
        for event, key, value in [('attempt','p','0.1'), ('attempt','side','"theirs"'), ('attempt','reason','"blocked"'),
                                  ('result','hit','0'), ('result','counted','0'), ('result','attempt','999'),
                                  ('state','ours_variance','0.9'), ('state','rarity','9'), ('state','marker','90'), ('state','weight','0.9'), ('state','ours_percent','"+10%"'), ('state','theirs_tone','"good"'),
                                  ('end','ours_hits','999'), ('push','ours_percent','"invented"'), ('ui','ours_tone','"bad"'), ('ui','emphasis','0.1'), ('ui','left','"99%25"')]:
            with self.subTest(event=event, key=key):
                status, output = self.replay(self.change(event,key,value))
                self.assertEqual(status, 1, output)

    def test_overview_context_rejects_wrong_direction_and_sample(self):
        for event in ('push', 'ui'):
            for key, value in [('swing', '"Net hit swing: 2.60 hits in your favour."'),
                               ('sample', '"Counted attacks: 1."'), ('text', '"Even"')]:
                with self.subTest(event=event, key=key):
                    status, output = self.replay(self.change(event, key, value, surface='results'))
                    self.assertEqual(status, 1, output)

    def test_nonfinite_invalid_boolean_and_duplicate_fields_fail(self):
        for event,key,value in [('attempt','p','nan'), ('state','rarity','inf'), ('ui','left','"nan%25"'),
                                ('attempt','enabled','2'), ('attempt','attempt','1.5'), ('attempt','p','-0.2')]:
            with self.subTest(event=event, key=key, value=value):
                status, output = self.replay(self.change(event,key,value))
                self.assertEqual(status, 1, output)
        lines = self.lines.copy(); lines[1] += ' p=0.7'
        status, output = self.replay(lines)
        self.assertEqual(status, 1, output)
        self.assertIn('duplicate field p', output)

    def test_partial_session_and_missing_ui_receipts_are_not_success(self):
        status, output = self.replay(self.lines[:15])
        self.assertNotEqual(status, 0, output)
        self.assertIn('no end', output)
        # A complete contiguous journal can honestly report that UI was unavailable.
        lines = [s for s in self.lines if 'event=ui ' not in s]
        lines = self.renumber(lines)
        status, output = self.replay(lines)
        self.assertEqual(status, 2, output)
        self.assertIn('no render receipt', output)

    def test_missing_publications_and_render_after_destruction_fail(self):
        lines = self.lines.copy()
        # Remove a complete push/receipt pair, so only the publication invariant catches it.
        index = next(i for i,s in enumerate(lines) if 'event=push ' in s)
        del lines[index:index+2]
        lines = self.renumber(lines)
        status, output = self.replay(lines)
        self.assertEqual(status, 1, output)
        self.assertIn('missing push', output)
        lines = self.lines.copy()
        destroy = next(i for i,s in enumerate(lines) if 'status="destroyed"' in s and 'surface="battle"' in s)
        entry = lines.pop(destroy)
        render = next(i for i,s in enumerate(lines) if 'status="rendered"' in s)
        pid = re.search(r'\bpush=(\d+)',lines[render])[1]
        entry = re.sub(r'\bpush=\d+', 'push='+pid, entry)
        lines.insert(render+1, entry)
        lines = self.renumber(lines)
        status, output = self.replay(lines)
        self.assertEqual(status, 1, output)
        self.assertIn('render after destruction', output)

    def test_delayed_ui_receipt_can_interleave_squirrel_checkpoints(self):
        lines = self.lines.copy()
        index = next(i for i,s in enumerate(lines) if '[xBroUI]' in s)
        delayed = lines.pop(index)
        second = [i for i,s in enumerate(lines) if 'event=result ' in s][1]
        lines.insert(second+1, delayed)
        status, output = self.replay(lines)
        self.assertEqual(status, 0, output)

    def test_missing_entire_results_surface_is_incomplete(self):
        lines = self.renumber([s for s in self.lines if 'surface="results"' not in s])
        status, output = self.replay(lines)
        self.assertEqual(status, 2, output)
        self.assertIn('no results payload observed', output)

    def test_no_battle_is_incomplete(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = audit.audit_journal('[xBro] schema=2 seq=1 battle=0 event=settings enabled=1 min_attacks=8')
        self.assertEqual(status, 2)
        self.assertIn('no numbered battle', out.getvalue())

    def test_external_runtime_error_is_not_ignored(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = audit.audit_journal(self.text+'xBro capture failed: test\n')
        self.assertEqual(status, 1)
        self.assertIn('runtime error', out.getvalue())

    def test_legacy_schema_two_still_replays_and_mixed_schemas_fail(self):
        lines = [
            '[xBro] schema=2 seq=1 battle=1 event=start version="0.3.0" model="displayed_chance_v1" enabled=1 min_attacks=8',
            '[xBro] schema=2 seq=2 battle=1 event=end attempts=0 results=0 excluded=0 errors=0 attack=0 ours_n=0 ours_hits=0 ours_expected=0 ours_variance=0 theirs_n=0 theirs_hits=0 theirs_expected=0 theirs_variance=0 z=0 rank=50 offset=0 pending=1 enabled=1 min_attacks=8 text=""',
            '[xBro] schema=2 seq=3 battle=1 event=close ended=1']
        status, output = self.replay(lines)
        self.assertEqual(status, 2, output)
        self.assertIn('0 errors', output)
        status, output = self.replay([line.replace('rank=50', 'rank=51') for line in lines])
        self.assertEqual(status, 1, output)
        self.assertIn('rank', output)
        status, output = self.replay(lines + self.lines)
        self.assertEqual(status, 1, output)
        self.assertIn('mixed schema', output)

    def test_pricing_reference_exposes_existing_model_discrepancies(self):
        e = {'enabled':'1', 'target_present':'1', 'alive':'1', 'attackable':'1', 'uses_hitchance':'1',
             'able_to_die':'1', 'by_faction':'2', 'on_faction':'1', 'player_faction':'1', 'side':'theirs',
             'ranged':'0', 'difficulty':'0', 'by_controlled':'0', 'on_controlled':'1', 'chance':'50',
             'shift':'-5', 'shifted':'45', 'initial_p':'.45', 'reroll':'10', 'p':'.42525'}
        reason, p, reference = audit.pricing(e)
        self.assertEqual(reason, 'counted')
        self.assertAlmostEqual(p, .42525)
        self.assertAlmostEqual(reference, .4275)
        e.update(difficulty='1', chance='74.5', shift='0', shifted='74.5', initial_p='.745', reroll='0', p='.745')
        _, p, reference = audit.pricing(e)
        self.assertAlmostEqual(p, .745)
        self.assertAlmostEqual(reference, .74)

    def test_all_exclusion_reasons_derive_from_the_recorded_branch_inputs(self):
        cases = [({'enabled':'0'}, 'disabled'), ({'enabled':'1','target_present':'0'}, 'null_target')]
        base = {'enabled':'1','target_present':'1','alive':'1','attackable':'1','uses_hitchance':'1','able_to_die':'1',
                'by_faction':'1','on_faction':'2','player_faction':'1','side':'ours','ranged':'1','projectile':'1',
                'allow_diversion':'1','distance':'4','blockers':'1'}
        for change, reason in [({'alive':'0'},'dead_target'), ({'attackable':'0'},'unattackable_target'),
                               ({'uses_hitchance':'0'},'no_hitchance'), ({'able_to_die':'0','hp':'1'},'unkillable'),
                               ({'on_faction':'1'},'outside_sample'), ({'allow_diversion':'0'},'diverted'), ({},'blocked')]:
            cases.append((dict(base,**change), reason))
        for e,reason in cases:
            self.assertEqual(audit.pricing(e), (reason,None,None))


if __name__ == '__main__':
    unittest.main()
