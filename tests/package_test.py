"""Release archive identity, reproducibility, safety, and source-integrity checks."""
from pathlib import Path, PurePosixPath
import subprocess
import sys
import unittest
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT = ROOT / 'dist' / 'mod_battle_luck_meter-1.0.0.zip'
MEMBERS = {
    'scripts/!mods_preload/mod_battle_luck_meter.nut',
    'scripts/mods/battle_luck_meter/capture.nut',
    'scripts/mods/battle_luck_meter/core.nut',
    'scripts/mods/battle_luck_meter/stats.nut',
    'scripts/mods/battle_luck_meter/ui.nut',
    'ui/mods/battle_luck_meter/battle_luck_meter.css',
    'ui/mods/battle_luck_meter/battle_luck_meter.js',
    'LICENSE',
    'README.md',
    'THIRD_PARTY.md',
    'docs/DEVELOPMENT.md',
}


class PackageTests(unittest.TestCase):
    def build(self):
        result = subprocess.run(
            [sys.executable, 'tools/package.py'], cwd=ROOT, text=True, capture_output=True, check=True)
        self.assertEqual(result.stderr, '')
        self.assertIn('dist/mod_battle_luck_meter-1.0.0.zip', result.stdout)
        return ARTIFACT.read_bytes()

    def test_archive_is_deterministic_safe_and_source_identical(self):
        first = self.build()
        second = self.build()
        self.assertEqual(first, second)
        with ZipFile(ARTIFACT) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(set(archive.namelist()), MEMBERS)
            for name in archive.namelist():
                path = PurePosixPath(name)
                self.assertFalse(path.is_absolute() or '..' in path.parts, name)
                self.assertNotIn('x' + 'bro', name.lower())
                self.assertEqual(archive.read(name), (ROOT / name).read_bytes(), name)


if __name__ == '__main__':
    unittest.main()
