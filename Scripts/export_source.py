#!/usr/bin/env python3
"""Create an allowlisted GitHub source ZIP; never package the workspace."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('destination', type=Path)
args = parser.parse_args()
subprocess.run(['python3', str(ROOT / 'Scripts/check_licenses.py')], check=True)
args.destination.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='windownest-source-') as temporary:
    export = Path(temporary) / 'WindowNest'
    export.mkdir()
    for directory in ['Sources', 'Resources', 'Vendor', 'CardinalBridge', 'Licenses', 'Scripts', 'Tests']:
        shutil.copytree(ROOT / directory, export / directory, symlinks=True, ignore=shutil.ignore_patterns('.DS_Store', '__pycache__', '*.pyc', 'target', '*.app'))
    for name in ['build.sh', 'build-cardinal.sh', '.gitignore', 'LICENSE-SCOPE.md', 'GITHUB_RELEASE.md', 'OPEN_SOURCE_AUDIT.md', 'SECURITY.md', 'CARDINAL-INTEGRATION.md']:
        shutil.copyfile(ROOT / name, export / name)
    for script in ROOT.glob('test*.sh'):
        shutil.copyfile(script, export / script.name)
    shutil.copyfile(ROOT / 'README-GITHUB.md', export / 'README.md')
    # Owner license is included if the owner has chosen one separately.
    if (ROOT / 'LICENSE').is_file():
        shutil.copyfile(ROOT / 'LICENSE', export / 'LICENSE')
    forbidden = {'.env', '.DS_Store', 'desktop-boxes.json', 'quick-folders.json', 'appearance.json'}
    secret = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]{20,}|ghp_[A-Za-z0-9]{30,}|sk-proj-[A-Za-z0-9_-]{30,}')
    assert not any(p.is_symlink() for p in export.rglob('*')), 'Do not export symlink targets'
    files = sorted(p for p in export.rglob('*') if p.is_file())
    for path in files:
        assert path.name not in forbidden and path.suffix not in {'.p12', '.pfx', '.pem', '.key', '.log', '.dylib'}, 'Unexpected local/private file in export'
        assert not path.is_symlink(), 'Do not export external symlink targets'
        content = path.read_bytes()
        assert not secret.search(content), 'Potential credential: ' + str(path.relative_to(export))
        assert str(Path.home()).encode() not in content, 'Developer-specific home path in export: ' + str(path.relative_to(export))
    subprocess.run(['python3', str(export / 'Scripts/check_licenses.py')], check=True)
    inventory = {str(p.relative_to(export)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (export / 'SOURCE-MANIFEST.json').write_text(json.dumps(inventory, indent=2) + '\n')
    with zipfile.ZipFile(args.destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(export.rglob('*')):
            if path.is_file():
                archive.write(path, 'WindowNest/' + str(path.relative_to(export)))
print('Created allowlisted GitHub source ZIP:', args.destination)
