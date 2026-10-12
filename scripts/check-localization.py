#!/usr/bin/env python3
"""Validate app localization tables. Deliberately not a proof of UI coverage."""
import argparse, collections, json, plistlib, re
from pathlib import Path
ENTRY=re.compile(r'\s*("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;',re.S)
TOKEN=re.compile(r'%(?:(\d+)\$)?(?:[-+0 #]*\d*(?:\.\d+)?)?(@|lld|ld|d|u|f|g|s)|%#@([A-Za-z0-9_]+)@')
def placeholders(s):
    s=s.replace('%%',''); out=[]; n=0
    for m in TOKEN.finditer(s):
        if m[3]: out.append(('plural',m[3]));continue
        n+=1; out.append((int(m[1] or n),m[2]))
    return sorted(out,key=str)
def table(path):
    text=re.sub(r'/\*.*?\*/','',path.read_text(),flags=re.S); pos=0;out={}
    while text[pos:].strip():
        m=ENTRY.match(text,pos)
        if not m: raise ValueError(f'{path}: invalid entry near {text[pos:pos+60]!r}')
        k,v=map(json.loads,m.groups())
        if k in out: raise ValueError(f'{path}: duplicate {k}')
        out[k]=v;pos=m.end()
    return out

def validate(root, required_keys=()):
    tables={}; plurals={}
    for lang in ['en','zh-Hans']:
        d=root/(lang+'.lproj');tables[lang]=table(d/'Localizable.strings')
        plurals[lang]=plistlib.loads((d/'Localizable.stringsdict').read_bytes())
        for key,entry in plurals[lang].items():
            if key in tables[lang]: raise ValueError(f'duplicate table/plural {key}')
            fmt=entry.get('NSStringLocalizedFormatKey','')
            if fmt!='%#@n@': raise ValueError(f'{lang}.{key}: renderer requires the n plural variable')
            for name in re.findall(r'%#@(\w+)@',fmt):
                var=entry.get(name,{})
                if var.get('NSStringFormatSpecTypeKey')!='NSStringPluralRuleType' or var.get('NSStringFormatValueTypeKey')!='lld' or 'other' not in var:
                    raise ValueError(f'{lang}.{key}: invalid plural {name}')
                if lang=='en' and 'one' not in var: raise ValueError(f'{key}: missing English one')
    if tables['en'].keys()!=tables['zh-Hans'].keys():raise ValueError('English/Chinese key sets differ')
    if plurals['en'].keys()!=plurals['zh-Hans'].keys():raise ValueError('Plural key sets differ')
    missing=set(required_keys)-tables['en'].keys()-plurals['en'].keys()
    if missing: raise ValueError('Required UI keys missing: '+', '.join(sorted(missing)))
    for k,v in tables['en'].items():
        if placeholders(v)!=placeholders(tables['zh-Hans'][k]):raise ValueError(f'{k}: placeholders differ')
    for k,v in plurals['en'].items():
        z=plurals['zh-Hans'][k]
        if placeholders(v['NSStringLocalizedFormatKey'])!=placeholders(z['NSStringLocalizedFormatKey']):raise ValueError(f'{k}: plural placeholders differ')
        for n in re.findall(r'%#@(\w+)@',v['NSStringLocalizedFormatKey']):
            for lang,entry in [('en',v[n]),('zh-Hans',z[n])]:
                for form in ['one','other']:
                    if form in entry and placeholders(entry[form])!=[(1,'lld')]:raise ValueError(f'{k}.{lang}.{form}: count placeholder required')
    return len(tables['en']),len(plurals['en'])
if __name__=='__main__':
    default=Path(__file__).resolve().parents[1]/'Sources/DigUpLocalizationResources/Resources'
    p=argparse.ArgumentParser()
    p.add_argument('--resources',type=Path,default=default)
    p.add_argument('--required-keys',type=Path)
    a=p.parse_args()
    try:
        manifest=a.required_keys or (Path(__file__).with_name('ui-localization-required-keys.json') if a.resources==default else None)
        required=json.loads(manifest.read_text()) if manifest and manifest.exists() else []
        n,m=validate(a.resources,required);print(f'Localization OK: {n} text keys, {m} plural keys per language; {len(required)} reviewed UI keys')
    except (ValueError,OSError,KeyError) as e:p.exit(1,f'Localization FAILED: {e}\n')
