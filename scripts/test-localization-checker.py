#!/usr/bin/env python3
import json, plistlib, subprocess, tempfile, unittest
from pathlib import Path
SCRIPT=Path(__file__).with_name('check-localization.py')
class CheckerTests(unittest.TestCase):
    def fixture(self, en=None, zh=None, plural=None):
        t=tempfile.TemporaryDirectory(); self.addCleanup(t.cleanup); root=Path(t.name)
        for lang, data in [('en',en or {'a':'Hello %@'}),('zh-Hans',zh or {'a':'你好 %@'})]:
            d=root/(lang+'.lproj'); d.mkdir()
            (d/'Localizable.strings').write_text('\n'.join(f'{json.dumps(k)} = {json.dumps(v,ensure_ascii=False)};' for k,v in data.items()))
            (d/'Localizable.stringsdict').write_bytes(plistlib.dumps(plural or {}))
        return root
    def run_check(self,root):
        return subprocess.run(['python3',str(SCRIPT),'--resources',str(root)],capture_output=True,text=True)
    def test_valid_resources(self):
        p=self.run_check(self.fixture()); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
    def test_duplicate_rejected(self):
        r=self.fixture(); p=r/'en.lproj/Localizable.strings';p.write_text(p.read_text()+'\n"a"="Duplicate %@";');self.assertNotEqual(self.run_check(r).returncode,0)
    def test_missing_english_rejected(self):
        self.assertNotEqual(self.run_check(self.fixture(zh={'a':'你好 %@','b':'额外'})).returncode,0)
    def test_placeholder_mismatch_rejected(self):
        self.assertNotEqual(self.run_check(self.fixture(zh={'a':'你好 %lld'})).returncode,0)
    def test_plural_missing_other_rejected(self):
        p={'count':{'NSStringLocalizedFormatKey':'%#@n@','n':{'NSStringFormatSpecTypeKey':'NSStringPluralRuleType','NSStringFormatValueTypeKey':'lld','one':'%lld file'}}}
        self.assertNotEqual(self.run_check(self.fixture(plural=p)).returncode,0)
if __name__=='__main__': unittest.main()
