"""Benign injection control, real helper I/O and old-cache compatibility.

Uses only synthetic files and throwaway copies of our own executables.
"""
import json
import os
from pathlib import Path
import queue
import shutil
import stat
import subprocess
import sys
import tempfile
import threading

app, base, old_helper = map(lambda value: Path(value).resolve(), sys.argv[1:4])
base.mkdir(parents=True, exist_ok=True)
main = app / 'Contents/MacOS/WindowNest'
helper = app / 'Contents/Helpers/WindowNestCardinal'
checks = 0

def check(value, message):
    global checks
    if not value:
        raise AssertionError(message)
    checks += 1

for executable in [main, helper]:
    for arch in ['arm64', 'x86_64']:
        details = subprocess.check_output(['codesign', '-dv', '--verbose=4', '--arch', arch, str(executable)], stderr=subprocess.STDOUT).decode()
        check('runtime)' in details, f'Missing hardened runtime: {executable.name}/{arch}')
    requirements = subprocess.check_output(['codesign', '-d', '-r-', str(executable)], stderr=subprocess.STDOUT).decode()
    check('cdhash' in requirements or 'anchor apple generic' in requirements, 'Identifier-only signature requirement retained')
    entitlements = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(executable)], stderr=subprocess.STDOUT)
    check(not any(key in entitlements for key in [b'get-task-allow', b'disable-library-validation', b'allow-dyld-environment-variables', b'allow-unsigned-executable-memory']), 'Unsafe runtime exception enabled')
check(b'/Users/' not in helper.read_bytes(), 'Helper still embeds a developer home path')

with tempfile.TemporaryDirectory(prefix='hardening-', dir=base) as temporary:
    root = Path(temporary)
    source = root / 'injection.c'
    source.write_text('#include <stdlib.h>\n#include <fcntl.h>\n#include <unistd.h>\n__attribute__((constructor)) static void marker(void) { const char *p=getenv("WINDOW_NEST_TEST_MARKER"); if(p) { int f=open(p,O_WRONLY|O_CREAT|O_TRUNC,0600); if(f>=0) { write(f,"loaded",6); close(f); } } }\n')
    library = root / 'marker.dylib'
    subprocess.run(['xcrun', 'clang', '-dynamiclib', str(source), '-o', str(library)], check=True, capture_output=True)
    # The app's NSApplication registration requires a desktop launch context;
    # exercise injection dynamically on the non-UI helper. Both app slices are
    # checked above, and the app is launched through the native UI separately.
    for executable in [helper]:
        normal_arguments = [str(executable), '--diagnose'] if executable == main else [str(executable)]
        baseline = subprocess.run(normal_arguments, input='', text=True, capture_output=True, timeout=20)
        check(baseline.returncode == 0, f'{executable.name} failed normal startup without injection')
        control = root / ('control-' + executable.name)
        shutil.copyfile(executable, control); control.chmod(0o700)
        subprocess.run(['codesign', '--remove-signature', str(control)], check=True, capture_output=True)
        subprocess.run(['codesign', '--sign', '-', '--identifier', 'local.windownest.temporary-injection-control', str(control)], check=True, capture_output=True)
        for binary, should_load in [(control, True), (executable, False)]:
            marker = root / ('marker-' + binary.name)
            environment = dict(os.environ, DYLD_INSERT_LIBRARIES=str(library), WINDOW_NEST_TEST_MARKER=str(marker))
            arguments = [str(binary), '--diagnose'] if executable == main else [str(binary)]
            result = subprocess.run(arguments, env=environment, input='', text=True, capture_output=True, timeout=20)
            if should_load:
                check(result.returncode == 0, f'{executable.name}: non-hardened positive control failed to load')
            else:
                # dyld may ignore the variable or reject startup; neither may
                # execute the injected constructor. Normal startup was checked.
                check(result.returncode in (0, -6, -9), f'Unexpected injection result: {result.returncode}')
            check(marker.exists() == should_load, 'Injection test lacked a positive control or hardened runtime allowed the marker')

    corpus = root / 'synthetic corpus'; corpus.mkdir()
    (corpus / '研究报告.txt').write_text('synthetic data')
    cache = root / 'private-cache' / 'index.zstd'
    def start_engine(binary):
        process = subprocess.Popen([str(binary), str(corpus), str(cache)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        events = queue.Queue()
        def read():
            for line in process.stdout:
                events.put(json.loads(line))
        threading.Thread(target=read, daemon=True).start()
        while True:
            event = events.get(timeout=30)
            if event['event'] == 'error':
                raise AssertionError(event)
            if event['event'] == 'ready':
                return process, events, event
    process, events, ready = start_engine(old_helper)
    process.stdin.close(); process.wait(timeout=10)
    os.chmod(cache.parent, 0o755); os.chmod(cache, 0o644)
    process, events, ready = start_engine(helper)
    try:
        check(ready['restored'], 'Security update could not load an old index')
        check(stat.S_IMODE(cache.parent.stat().st_mode) == 0o700, 'Legacy cache directory was not restricted')
        check(stat.S_IMODE(cache.stat().st_mode) == 0o600, 'Legacy cache file was not restricted')
        process.stdin.write(json.dumps({'id': 1, 'query': '报告 ext:txt', 'limit': 300}) + '\n'); process.stdin.flush()
        while True:
            event = events.get(timeout=20)
            if event.get('id') == 1:
                check(event.get('total') == 1, 'Hardened helper failed a real Unicode query')
                break
    finally:
        process.stdin.close(); process.wait(timeout=10)
    cache.unlink()
    process, events, ready = start_engine(helper)
    process.stdin.close(); process.wait(timeout=10)
    check(stat.S_IMODE(cache.stat().st_mode) == 0o600, 'New compressed index was not private')
print(f'Passed {checks} signature, benign injection, cache-permission and helper compatibility checks')
