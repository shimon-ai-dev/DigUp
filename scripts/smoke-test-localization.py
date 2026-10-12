#!/usr/bin/env python3
"""Verify a moved, signed app loads its own localized resources, without launching its UI."""
import argparse, json, os, plistlib, shutil, subprocess, tempfile, signal
from pathlib import Path

KEYS=['NSAppleEventsUsageDescription','NSDesktopFolderUsageDescription','NSDocumentsFolderUsageDescription','NSDownloadsFolderUsageDescription','NSRemovableVolumesUsageDescription']
BUNDLE='DigUp_DigUpLocalizationResources.bundle'
def run(*args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, timeout=45, **kwargs)
def side_effect_snapshot():
    # Only inspect existence/metadata of these test app locations on the ephemeral CI runner.
    home=Path.home()
    roots=[home/'Library/Application Support/DigUpTest',home/'Library/Caches/DigUpTest',home/'Library/Preferences/io.github.xieshiqi147258.DigUp.ci.plist']
    result={}
    for root in roots:
        for p in ([root]+list(root.rglob('*')) if root.is_dir() else [root]):
            if p.exists():
                st=p.stat();result[str(p)]=(st.st_size,st.st_mtime_ns)
    return result

def check(source):
    assert source.suffix=='.app' and source.is_dir(), source
    info=plistlib.loads((source/'Contents/Info.plist').read_bytes())
    assert set(info['CFBundleLocalizations'])=={'en','zh-Hans'}
    resources=source/'Contents/Resources'
    assert (resources/BUNDLE).is_dir(), 'Missing packaged localization bundle'
    for language in ['en','zh-Hans']:
        assert (resources/(language+'.lproj')/'InfoPlist.strings').is_file(), language
    with tempfile.TemporaryDirectory(prefix='DigUpLocalizationSmoke-') as t:
        app=Path(t)/'Moved.app';shutil.copytree(source,app,symlinks=True)
        verify=run('codesign','--verify','--deep','--strict',str(app))
        assert verify.returncode==0,verify.stderr
        executable=app/'Contents/MacOS'/info['CFBundleExecutable']
        repo=Path(__file__).resolve().parents[1];build=repo/'.build';hidden=repo/('.build-localization-hidden-'+str(os.getpid()))
        before=side_effect_snapshot()
        try:
            if build.exists():
                assert not hidden.exists();build.rename(hidden)
            for preference,language,cancel,pause in [('en','en','Cancel','Pause Indexing'),('zh-Hans','zh-Hans','取消','暂停索引'),('ja','en','Cancel','Pause Indexing')]:
                result=run(str(executable),'--localization-smoke','-AppleLanguages',f'({preference})',cwd=t)
                assert result.returncode==0,result.stderr
                data=json.loads(result.stdout)
                assert data['language']==language and data['cancel']==cancel and data['pause']==pause,data
                assert data['results']==('2 个结果' if language=='zh-Hans' else '2 results'),data
                assert Path(data['resourcePath']).resolve().is_relative_to(app.resolve()),data
                assert set(data['permissions'])==set(KEYS),data
                for key,value in data['permissions'].items():
                    assert value and (any('\u4e00'<=c<='\u9fff' for c in value) if language=='zh-Hans' else value==info[key]),(key,value)
                print(f'PASS moved app: {preference} -> {language}, in-app resources and five purpose strings')
            assert side_effect_snapshot()==before,'Read-only smoke changed test app data'
            shutil.rmtree(app/'Contents/Resources'/BUNDLE)
            bad=run(str(executable),'--localization-smoke','-AppleLanguages','(en)',cwd=t)
            assert bad.returncode==2 and 'Localization smoke failed' in bad.stderr,(bad.returncode,bad.stderr)
            assert side_effect_snapshot()==before,'Missing-resource probe changed test app data'
            print('PASS missing resource: fails closed, no developer-bundle fallback')
        finally:
            if hidden.exists():
                assert not build.exists();hidden.rename(build)
def interrupted(signum, frame):
    raise SystemExit(128+signum)

if __name__=='__main__':
    signal.signal(signal.SIGTERM,interrupted)
    p=argparse.ArgumentParser();p.add_argument('app',type=Path);a=p.parse_args();check(a.app.resolve())
