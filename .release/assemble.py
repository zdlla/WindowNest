import hashlib
import json
import os
from pathlib import Path

plan=json.loads(Path('.release/plan.json').read_text())
output=Path(os.environ['RUNNER_TEMP'])/'windownest-release';output.mkdir(exist_ok=True)
for file in plan['files']:
    assert Path(file['name']).name==file['name']
    digest=hashlib.sha256();size=0
    with (output/file['name']).open('wb') as target:
        for part in file['parts']:
            assert part.startswith('.release-parts/') and '..' not in Path(part).parts
            data=Path(part).read_bytes();target.write(data);digest.update(data);size+=len(data)
    assert size==file['bytes'] and digest.hexdigest()==file['sha256'],file['name']
manifest=json.loads((output/'update-manifest.json').read_text())
archive=next(file for file in plan['files'] if file['name']==manifest['artifact'])
assert manifest['repository']=='zdlla/WindowNest' and manifest['version']==plan['version']
assert manifest['sha256']==archive['sha256'] and manifest['bytes']==archive['bytes']
print('All release artifacts matched their SHA-256 and signed-manifest metadata')
