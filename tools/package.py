"""Build a deterministic release archive from owned runtime files and distribution docs."""
from hashlib import sha256
from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent


def package(destination, sources):
    destination.parent.mkdir(exist_ok=True)
    with ZipFile(destination, 'w', ZIP_DEFLATED) as archive:
        for name, path in sorted(sources.items()):
            info = ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())
    with ZipFile(destination) as archive:
        assert archive.testzip() is None
    print(f'{destination.relative_to(ROOT)}: {len(sources)} files; ZIP integrity passed\n'
          f'SHA256 {sha256(destination.read_bytes()).hexdigest()}')


version = re.search(r'Version = "([0-9.]+)"', (ROOT / 'scripts/mods/xbro/core.nut').read_text())[1]
paths = [*ROOT.glob('scripts/mods/xbro/*.nut'),
         *(ROOT / name for name in ('scripts/!mods_preload/mod_xbro.nut', 'ui/mods/xbro/xbro.js', 'ui/mods/xbro/xbro.css',
                                    'LICENSE', 'README.md', 'THIRD_PARTY.md', 'docs/DEVELOPMENT.md'))]
package(ROOT / 'dist' / f'mod_xbro-{version}.zip', {path.relative_to(ROOT).as_posix(): path for path in paths})
