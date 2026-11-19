"""Exercise only the replacement helper with owned dummy apps and settings."""
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

source=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='WindowNest-update-preservation-',suffix='.noindex') as temporary:
    root=Path(temporary)
    code=root/'stub.c';code.write_text('int main(void) { return 0; }\n')
    binary=root/'stub';subprocess.run(['xcrun','clang',str(code),'-o',str(binary)],check=True)
    def make_app(path,version):
        (path/'Contents/MacOS').mkdir(parents=True)
        shutil.copyfile(binary,path/'Contents/MacOS/WindowNest');(path/'Contents/MacOS/WindowNest').chmod(0o755)
        (path/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.windownest.app','CFBundleExecutable':'WindowNest','CFBundleShortVersionString':version,'CFBundleVersion':'48','CFBundlePackageType':'APPL'}))
        subprocess.run(['codesign','--force','--sign','-',str(path)],check=True,capture_output=True)
    user=root/'Application Support/WindowNest';user.mkdir(parents=True)
    sentinel=user/'desktop-boxes.json';original=b'{"fixture":"theme, bookmarks, layout and settings"}\n';sentinel.write_bytes(original);sentinel.chmod(0o600)
    target=root/'Applications/窗匣.app';make_app(target,'0.19.9')
    work=user/'Updates/owned.noindex';staged=work/'payload/窗匣.app';make_app(staged,'0.20.0')
    command=['/bin/sh',str(source/'Resources/install-update.sh'),'99999999',str(staged),str(target),str(work),'--no-launch']
    subprocess.run(command,check=True,capture_output=True)
    assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='0.20.0'
    assert sentinel.read_bytes()==original and sentinel.stat().st_mode&0o777==0o600
    assert (work/'previous.zip').is_file() and not staged.exists()
    badwork=user/'Updates/bad.noindex';bad=badwork/'payload/窗匣.app';make_app(bad,'0.20.1')
    with (bad/'Contents/MacOS/WindowNest').open('ab') as f:f.write(b'tampered')
    result=subprocess.run(['/bin/sh',str(source/'Resources/install-update.sh'),'99999999',str(bad),str(target),str(badwork),'--no-launch'],capture_output=True)
    assert result.returncode!=0
    assert plistlib.loads((target/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='0.20.0'
    assert sentinel.read_bytes()==original
    print('Passed app replacement, rollback ZIP, invalid-package refusal and exact preservation of settings bytes/permissions')
