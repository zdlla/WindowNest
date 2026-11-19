#!/usr/bin/env python3
"""Offline release gate for the exact locked helper graph and notice payload."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def locked_registry():
    records = []
    for block in (ROOT / 'CardinalBridge/Cargo.lock').read_text().split('[[package]]')[1:]:
        fields = dict(re.findall(r'^(name|version|source|checksum) = "([^"]+)"$', block, re.M))
        if fields.get('source', '').startswith('registry+'):
            records.append(fields)
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path)
    args = parser.parse_args()
    inventory = json.loads((ROOT / 'Licenses/DEPENDENCIES.json').read_text())
    assert (ROOT / 'LICENSE').read_bytes() == (ROOT / 'Licenses/WindowNest-MIT.txt').read_bytes(), 'Project MIT copies differ'
    assert inventory.get('rustStandardLibrary', {}).get('noticeFiles'), 'Missing Rust standard-library notice'
    expected = {(r['name'], r['version']): r for r in locked_registry()}
    actual = {(r['name'], r['version']): r for r in inventory['rustRegistryPackages']}
    assert set(expected) == set(actual), 'Cargo.lock changed: regenerate the dependency/notice inventory'
    assert inventory['cargoLockSHA256'] == hashlib.sha256((ROOT / 'CardinalBridge/Cargo.lock').read_bytes()).hexdigest(), 'Lockfile fingerprint changed'
    for key, record in actual.items():
        assert record['archiveSHA256'] == expected[key]['checksum'], 'Registry archive identity mismatch: ' + str(key)
        assert record['licenseDeclared'] and record['licenseSelected'], 'Unreviewed license: ' + str(key)
        assert record['licenseSelected'] in {'MIT', 'MIT AND Unicode-3.0', 'BSD-3-Clause', 'Zlib', 'WTFPL'}, 'New license requires manual review: ' + str(key)
        assert record['noticeFiles'], 'No retained notices: ' + str(key)
    for relative, digest in inventory['noticeSHA256'].items():
        path = ROOT / 'Licenses' / relative
        assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'Missing/changed notice: ' + relative
        if args.bundle:
            packaged = args.bundle / 'Contents/Resources/Licenses' / relative
            assert packaged.is_file() and hashlib.sha256(packaged.read_bytes()).hexdigest() == digest, 'Notice not shipped in app: ' + relative
    for component in inventory['components']:
        assert component['licenseFiles'], 'Missing direct-component license'
        assert not component.get('unresolved', False), 'Unresolved component license: ' + component['name']
    for relative, digest in inventory['svgSourceSHA256'].items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest, 'SVG source changed without license/provenance review'
    for name, digest in inventory['fileTypePNGSHA256'].items():
        assert hashlib.sha256((ROOT / 'Resources/FileTypeIcons' / name).read_bytes()).hexdigest() == digest, 'Changed generated icon'
        if args.bundle:
            assert hashlib.sha256((args.bundle / 'Contents/Resources/FileTypeIcons' / name).read_bytes()).hexdigest() == digest, 'Icon differs in packaged app'
    if args.bundle:
        assert (args.bundle / 'Contents/Resources/Licenses/DEPENDENCIES.json').read_bytes() == (ROOT / 'Licenses/DEPENDENCIES.json').read_bytes(), 'Packaged inventory differs'
    print('Verified %d locked Rust registry packages, %d direct components and %d notice files%s' % (
        len(actual), len(inventory['components']), len(inventory['noticeSHA256']), ' in the app bundle' if args.bundle else ''))


if __name__ == '__main__':
    main()
