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

    def change(self, event, key, value, surface=None, battle=None):
        lines = self.lines.copy()
        index = next(i for i,s in enumerate(lines) if f'event={event} ' in s and (surface is None or f'surface="{surface}"' in s)
                     and (battle is None or f' battle={battle} ' in s))
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
        self.assertTrue(any('event=start ' in line and 'version="0.4.6"' in line and
                            'model="displayed_chance_v2"' in line and
                            'ui_model="smoothed_percent_option_v1"' in line and 'show_percentages=0' in line
                            for line in self.lines))
        entries, errors = audit.journal(self.text)
        self.assertFalse(errors)
        self.assertTrue(any(e.get('on') == 'A" p=0 x="<>&%\n\\' for e in entries))
        beginner_lucky = next(e for e in entries if e.get('event') == 'attempt' and e.get('battle') == '9')
        self.assertAlmostEqual(float(beginner_lucky['p']), .995)

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
        with NamedTemporaryFile(mode='w', suffix='.nut', dir='/tmp') as tmp:
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
                                  ('state','ours_variance','0.9'), ('state','rarity','9'), ('state','midp','0.9'), ('state','z','1.5'),
                                  ('state','marker','90'), ('state','weight','0.9'), ('state','emphasis','1'), ('state','ours_percent','"+10%"'),
                                  ('state','ours_exact_percent','"+10%"'), ('state','ours_exact_tone','"bad"'), ('state','theirs_tone','"good"'),
                                  ('end','ours_hits','999'), ('push','ours_percent','"invented"'), ('start','show_percentages','1'),
                                  ('ui','emphasis','0.1'), ('ui','left','"99%25"')]:
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

    def battle(self, bid):
        return [s for s in self.lines if f' battle={bid} ' in s]

    # Rewrite the emitted 0.4.6 journal of a one-counted-attack battle into an earlier
    # released UI contract, so every shipped model keeps replaying under its own semantics.
    EXACT_FIELDS = ('ours_exact_percent', 'ours_exact_tone', 'theirs_exact_percent', 'theirs_exact_tone')

    @staticmethod
    def field(line, key):
        return re.search(rf'\b{key}=("[^"]*"|\S+)', line)[1]

    def rebase(self, lines, version, models, weight, damp_results=False):
        """Move the bar back onto the earlier percentile axis, with always-exact percentages.

        Every model before 0.4.5 put the live marker at `50 + (rarity - 50) * weight`; 0.4.1
        also showed that damped marker on the results screen, at the live warm-up emphasis.
        """
        state = next(s for s in lines if ' event=state ' in s)
        rarity, sigma = float(self.field(state, 'rarity')), float(self.field(state, 'marker'))
        exact = {key: self.field(state, key) for key in self.EXACT_FIELDS}
        live, out = 50 + (rarity - 50) * weight, []
        for line in lines:
            line = re.sub(r'version="[^"]*"', f'version="{version}"', line)
            line = line.replace(' model="displayed_chance_v2"', ' model="displayed_chance_v1"')
            line = line.replace(' marker_model="probit_evidence_weight_v1"', models[0])
            line = line.replace(' ui_model="smoothed_percent_option_v1"', models[1])
            line = re.sub(r' (' + '|'.join(self.EXACT_FIELDS) + r'|midp|z)=("[^"]*"|\S+)', '', line)
            for side in ('ours', 'theirs'):
                for kind in ('percent', 'tone'):
                    line = re.sub(rf'\b{side}_{kind}=("[^"]*"|\S+)',
                                  lambda m, value=exact[f'{side}_exact_{kind}'], key=f'{side}_{kind}': f'{key}={value}', line)
            line = re.sub(r'\bweight=\S+', f'weight={weight:.9g}', line)
            if 'surface="results"' not in line:
                line = re.sub(r'\bmarker=\S+', f'marker={live:.9g}', line)
                line = line.replace(f'left="{sigma:g}%25"', f'left="{live:g}%25"')
            elif damp_results:
                line = re.sub(r'\bmarker=\S+', f'marker={live:.9g}', line)
                line = re.sub(r'\bemphasis="?1"?(?=\s|$)', 'emphasis=0.55', line)
                line = line.replace(f'left="{rarity:g}%25"', f'left="{live:g}%25"')
                line = line.replace('sample="Small sample: 1 attack."',
                                    'sample="Small sample: 1 attack. Below 10 attacks, the bar stays closer to the centre."')
            out.append(line)
        return out

    def always_percentages(self, lines):
        """0.4.1/0.4.2 rendered both percentages unconditionally, so receipts always carry them."""
        readouts = {}
        for line in lines:
            if line.startswith('[xBro]') and ' event=push ' in line:
                readouts[self.field(line, 'push')] = {key: self.field(line, key) for key in audit.READOUT_FIELDS
                                                      if key not in ('marker', 'emphasis')}
        out = []
        for line in lines:
            line = re.sub(r' (show_percentages|badges)=("[^"]*"|\S+)', '', line)
            if line.startswith('[xBroUI]') and 'status="rendered"' in line:
                for key in audit.READOUT_FIELDS:
                    if key not in ('marker', 'emphasis'):
                        line = re.sub(rf' {key}=("[^"]*"|\S+)', '', line)
                line += ''.join(f' {key}={value}' for key, value in readouts[self.field(line, 'push')].items())
            out.append(line)
        return out

    def legacy(self, lines):
        """0.4.1: linear warm-up weight 0.1, results retaining that damping, old wording."""
        out = self.rebase(lines, '0.4.1', ('', ''), 0.1, damp_results=True)
        out = [line.replace('Bottom 5%25 of outcomes at these odds', 'Bottom 5%25 unluckiest battles') for line in out]
        out = [line + ' interpretation="' + audit.LEGACY_INTERPRETATION.replace("'", '%27') + '"'
               if 'event=tooltip ' in line else line for line in out]
        return self.renumber(self.always_percentages(out))

    def percentage_visible_0_4_2(self, lines):
        return self.renumber(self.always_percentages(
            self.rebase(lines, '0.4.2', (' marker_model="evidence_weight_v1"', ''), 1 / 11)))

    def bar_only_0_4_3(self, lines):
        out = self.rebase(lines, '0.4.3', (' marker_model="evidence_weight_v1"', ' ui_model="bar_only_v1"'), 1 / 11)
        return self.renumber([re.sub(r' (show_percentages|badges)=("[^"]*"|\S+)', '', line) if line.startswith('[xBro]')
                              else re.sub(r' ((ours|theirs)_(percent|tone)|badges)=("[^"]*"|\S+)', '', line) for line in out])

    def percent_option_0_4_4(self, lines):
        """0.4.4: the percentile axis with the same optional badges, rendered exact."""
        return self.renumber(self.rebase(lines, '0.4.4',
            (' marker_model="evidence_weight_v1"', ' ui_model="relative_percent_option_v1"'), 1 / 11))

    def probit_0_4_5(self, lines):
        """0.4.5: current UI semantics with the original shifted-reroll probability model."""
        return self.renumber([line.replace('version="0.4.6"', 'version="0.4.5"')
                              .replace('model="displayed_chance_v2"', 'model="displayed_chance_v1"')
                              for line in lines])

    def test_current_ui_receipts_are_conditional_and_reject_badge_tampering(self):
        self.assertTrue(any('event=start ' in line and 'version="0.4.6"' in line and
                            'model="displayed_chance_v2"' in line and
                            'ui_model="smoothed_percent_option_v1"' in line for line in self.lines))
        rendered = [line for line in self.lines if line.startswith('[xBroUI]') and 'status="rendered"' in line]
        hidden = [line for line in rendered if 'badges="hidden"' in line]
        visible = [line for line in rendered if 'badges="rendered"' in line]
        self.assertTrue(hidden and visible)
        for line in hidden:
            self.assertFalse(any(re.search(rf'\b{key}=', line) for key in audit.READOUT_FIELDS[2:]))
        for line in visible:
            self.assertTrue(all(re.search(rf'\b{key}=', line) for key in audit.READOUT_FIELDS[2:]))
        lines = self.lines.copy()
        index = next(i for i, line in enumerate(lines) if line.startswith('[xBroUI]') and 'badges="hidden"' in line)
        lines[index] += ' ours_percent="+1900%25"'
        status, output = self.replay(lines)
        self.assertEqual(status, 1, output)
        self.assertIn('hidden badge receipt contains a percentage readout', output)
        lines = self.lines.copy()
        index = next(i for i, line in enumerate(lines) if line.startswith('[xBroUI]') and 'badges="rendered"' in line)
        lines[index] = lines[index].replace('badges="rendered"', 'badges="hidden"')
        status, output = self.replay(lines)
        self.assertEqual(status, 1, output)
        self.assertIn('badges', output)
        lines = self.lines.copy()
        index = next(i for i, line in enumerate(lines) if line.startswith('[xBroUI]') and 'badges="rendered"' in line)
        lines[index] = re.sub(r'ours_tone="[^"]*"', 'ours_tone="neutral"', lines[index])
        status, output = self.replay(lines)
        self.assertEqual(status, 1, output)
        self.assertIn('ours_tone', output)

    def test_legacy_0_4_1_through_0_4_5_contracts_still_replay(self):
        emitted = self.battle(7)
        variants = [('0.4.1', self.legacy(emitted)), ('0.4.2', self.percentage_visible_0_4_2(emitted)),
                    ('0.4.3', self.bar_only_0_4_3(emitted)), ('0.4.4', self.percent_option_0_4_4(emitted)),
                    ('0.4.5', self.probit_0_4_5(emitted))]
        for version, lines in variants:
            with self.subTest(version=version):
                status, output = self.replay(lines)
                self.assertEqual(status, 0, output)
                self.assertIn('0 errors, 0 model discrepancies, 0 evidence gaps', output)
        lines = self.bar_only_0_4_3(emitted)
        index = next(i for i, line in enumerate(lines) if line.startswith('[xBroUI]') and 'status="rendered"' in line)
        lines[index] += ' ours_percent="+1900%25"'
        status, output = self.replay(lines)
        self.assertEqual(status, 1, output)
        self.assertIn('bar-only UI receipt contains a percentage readout', output)

    def test_the_results_surface_keeps_the_exact_percentages_and_the_bar_the_smoothed_ones(self):
        # Battle 7 is a single 95% miss: -100% exactly, -9% once weighted by 1/11.
        battle = self.battle(7)
        live = next(line for line in battle if ' event=push ' in line and 'surface="battle"' in line)
        final = next(line for line in battle if ' event=push ' in line and 'surface="results"' in line)
        self.assertIn('ours_percent="-9%25"', live)
        self.assertIn('ours_percent="-100%25"', final)
        for surface, wrong in [('battle', '"-100%25"'), ('results', '"-9%25"')]:
            with self.subTest(surface=surface):
                status, output = self.replay(self.change('push', 'ours_percent', wrong, surface=surface, battle=7))
                self.assertEqual(status, 1, output)
                self.assertIn('ours_percent', output)
        # The overview bar is the exact tail at full emphasis, not the live sigma position.
        status, output = self.replay(self.change('push', 'marker', '47.0303726', surface='results', battle=7))
        self.assertEqual(status, 1, output)
        self.assertIn('push: marker', output)

    def test_the_axis_is_checked_in_three_independent_steps(self):
        state = next(line for line in self.lines if ' event=state ' in line and ' battle=7 ' in line)
        for field in ('midp=0.025000006', 'z=-1.9599545', 'marker=47.0303726'):
            self.assertIn(field, state)
        # A mid-p tail that no longer matches the replayed distribution, an axis position
        # that no longer matches that tail, and a bar that no longer matches that position.
        for key, value, finding in [('midp', '0.03', 'state: midp'), ('z', '-1.97', 'state: z'),
                                    ('marker', '47.05', 'state: marker')]:
            with self.subTest(key=key):
                status, output = self.replay(self.change('state', key, value, battle=7))
                self.assertEqual(status, 1, output)
                self.assertIn(finding, output)
        # The float32 spread of the approximation is allowed on the axis itself, but the bar
        # is still pinned to the axis position the runtime wrote, so the edit surfaces there.
        status, output = self.replay(self.change('state', 'z', '-1.96', battle=7))
        self.assertEqual(status, 1, output)
        self.assertNotIn('state: z', output)
        self.assertIn('state: marker', output)

    def test_results_show_the_raw_tail_and_live_marker_is_evidence_weighted(self):
        for key, value in [('marker', '45.9090919'), ('emphasis', '0.55')]:
            with self.subTest(key=key):
                status, output = self.replay(self.change('push', key, value, surface='results'))
                self.assertEqual(status, 1, output)
                self.assertIn(f'push: {key}', output)

    def test_defective_checkpoint_is_reported_without_losing_the_battle_end(self):
        status, output = self.replay(self.change('end', 'ours_exact_percent', '"+63%25"', battle=8))
        self.assertEqual(status, 1, output)
        findings = [line for line in output.splitlines() if line.startswith(('ERROR:', 'INCOMPLETE:'))]
        self.assertEqual(len(findings), 1, output)
        self.assertIn("end: ours_exact_percent: wrote '+63%', derived '+64%'", findings[0])

    def test_current_journals_must_not_carry_legacy_tooltip_wording(self):
        tooltip = next(i for i, s in enumerate(self.lines) if 'event=tooltip ' in s and ' battle=7 ' in s)
        for edit in [lambda s: s + ' interpretation="' + audit.LEGACY_INTERPRETATION.replace("'", "%27") + '"',
                     lambda s: s.replace('swing="Net: 0.95', 'swing="Net hit swing: 0.95'),
                     lambda s: s.replace('ours="You: 0/1 hits vs 0.95 expected"', 'ours="You: 0/1 hit, 0.95 expected. 100%25 fewer hits than expected."')]:
            lines = self.lines.copy(); lines[tooltip] = edit(lines[tooltip])
            self.assertNotEqual(lines[tooltip], self.lines[tooltip])
            status, output = self.replay(lines)
            self.assertEqual(status, 1, output)
            self.assertIn('tooltip', output)

    def test_legacy_marker_model_replays_0_4_1_semantics_and_exposes_its_defects(self):
        emitted = self.battle(7)
        self.assertTrue(any('chance=95' in s for s in emitted))
        legacy = self.legacy(emitted)
        self.assertNotEqual(legacy, self.renumber(emitted))
        status, output = self.replay(legacy)
        self.assertEqual(status, 0, output)
        self.assertIn('0 errors, 0 model discrepancies, 0 evidence gaps', output)
        self.assertIn('Bottom 5% unluckiest battles', output)
        # The same runtime values under the current model are not accepted as 0.4.1 evidence and vice versa.
        status, output = self.replay(self.renumber([s.replace(' marker_model="probit_evidence_weight_v1"', '') for s in emitted]))
        self.assertEqual(status, 1, output)
        self.assertIn('marker: wrote 47.0', output)
        status, output = self.replay([s.replace('version="0.4.1"', 'version="0.4.2" marker_model="evidence_weight_v1"') for s in legacy])
        self.assertEqual(status, 1, output)
        self.assertIn('weight: wrote 0.1', output)
        # The 0.4.1 integer-abs defect: a 0.95-hit swing shown as even on both surfaces.
        defective = [re.sub(r'swing="(Net hit swing|Net): 0\.95 hits against you\."', r'swing="\1: even."', s) for s in legacy]
        self.assertEqual(sum(a != b for a, b in zip(defective, legacy)), 3)
        status, output = self.replay(defective)
        self.assertEqual(status, 1, output)
        self.assertEqual(output.count('net hit swing is not even'), 2, output)
        # ... and a +63.9% readout truncated to +63%, which the same journal shape must expose.
        percent = self.legacy(self.battle(8))
        self.assertEqual(self.replay(percent)[0], 0)
        defective = [s.replace('ours_percent="+64%25"', 'ours_percent="+63%25"') for s in percent]
        status, output = self.replay(defective)
        self.assertEqual(status, 1, output)
        self.assertIn("ours_percent: wrote '+63%', derived '+64%'", output)
        status, output = self.replay([s.replace('event=start ', 'event=start marker_model="other" ') for s in legacy])
        self.assertEqual(status, 1, output)
        self.assertIn('unsupported marker model', output)

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

    def test_pricing_replays_old_rerolls_and_current_rerolls_match_the_native_order(self):
        e = {'enabled':'1', 'target_present':'1', 'alive':'1', 'attackable':'1', 'uses_hitchance':'1',
             'able_to_die':'1', 'by_faction':'2', 'on_faction':'1', 'player_faction':'1', 'side':'theirs',
             'ranged':'0', 'difficulty':'0', 'by_controlled':'0', 'on_controlled':'1', 'chance':'50',
             'shift':'-5', 'shifted':'45', 'initial_p':'.45', 'reroll':'10', 'p':'.42525'}
        reason, p, reference = audit.pricing(e, 'displayed_chance_v1')
        self.assertEqual(reason, 'counted')
        self.assertAlmostEqual(p, .42525)
        self.assertAlmostEqual(reference, .4275)
        e['p'] = '.4275'
        reason, p, reference = audit.pricing(e, 'displayed_chance_v2')
        self.assertEqual(reason, 'counted')
        self.assertAlmostEqual(p, .4275)
        self.assertAlmostEqual(reference, .4275)
        e.update(difficulty='1', chance='74.5', shift='0', shifted='74.5', initial_p='.745', reroll='0', p='.745')
        _, p, reference = audit.pricing(e, 'displayed_chance_v2')
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
