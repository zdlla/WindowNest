"""Exercise the offline gate with disposable metadata/assets, never user data."""
import shutil
import subprocess
import tempfile
from pathlib import Path

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='windownest-license-gate-') as temporary:
    root = Path(temporary)
    shutil.copyfile(source / 'LICENSE', root / 'LICENSE')
    for name in ['Licenses', 'Resources/FileTypeIcons', 'Vendor/Lucide']:
        shutil.copytree(source / name, root / name)
    (root / 'CardinalBridge').mkdir()
    shutil.copyfile(source / 'CardinalBridge/Cargo.lock', root / 'CardinalBridge/Cargo.lock')
    (root / 'Scripts').mkdir()
    shutil.copyfile(source / 'Scripts/check_licenses.py', root / 'Scripts/check_licenses.py')
    def run(expected):
        result = subprocess.run(['python3', str(root / 'Scripts/check_licenses.py')], capture_output=True)
        assert (result.returncode == 0) == expected, result.stdout.decode() + result.stderr.decode()
    run(True)
    targets = [
        root / 'Licenses/Rust/unicode-normalization-0.1.26/COPYRIGHT',
        root / 'Vendor/Lucide/file-text.svg',
        root / 'Resources/FileTypeIcons/pdf.png',
        root / 'CardinalBridge/Cargo.lock',
    ]
    for path in targets:
        original = path.read_bytes()
        path.write_bytes(original + b'\nchanged without review\n')
        run(False)
        path.write_bytes(original)
    run(True)
print('Passed valid inventory and rejection of missing/changed copyright, source SVG, PNG and lockfile payloads')
