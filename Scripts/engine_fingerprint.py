#!/usr/bin/env python3
"""Detect stale prebuilt helpers after a source, dependency or flag change."""
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
files = [root / 'build-cardinal.sh', root / 'CardinalBridge/Cargo.lock']
for directory in ['CardinalBridge', 'Vendor/Cardinal']:
    files.extend(p for p in (root / directory).rglob('*') if p.suffix in {'.rs', '.toml'})
digest = hashlib.sha256()
for path in sorted(set(files)):
    digest.update(str(path.relative_to(root)).encode() + b'\0' + path.read_bytes() + b'\0')
print(digest.hexdigest())
