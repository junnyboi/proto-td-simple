#!/usr/bin/env python3
"""Install/verify the pinned compact common-Simplified-Chinese fallback."""
from pathlib import Path
import argparse, hashlib, json, re
ROOT=Path(__file__).resolve().parents[1]
FONT=ROOT/'assets/template/fonts/ManusGameSC-Common.woff2'
SHA256='150544e032d5a266d214799dbab5c6b6e9bad78645bdeaff5d11aba8cae43f7c'
REPERTOIRE_SHA256='12f677fdbc8c1890f9362d55b5090fc4d1c813f4e0150363bbae19528a82b92b'
MAX_BYTES=1000000

def verify():
    raw=FONT.read_bytes()
    if len(raw)>MAX_BYTES or hashlib.sha256(raw).hexdigest()!=SHA256:
        raise ValueError('Runtime CJK font must match the approved compact subset and stay at most 1,000,000 bytes')
    points_file=FONT.with_name('cjk-codepoints.json')
    if hashlib.sha256(points_file.read_bytes()).hexdigest()!=REPERTOIRE_SHA256 or len(json.loads(points_file.read_text()))!=6547:
        raise ValueError('The complete approved 6,547-codepoint repertoire must be retained')
    if 'SIL OPEN FONT LICENSE' not in FONT.with_name('NotoSansCJK-COPYRIGHT.txt').read_text():
        raise ValueError('Missing CJK license')
    for name in ('manuscc0_font','manuscc0_medium_font','manuscc0_bold_font'):
        text=(ROOT/'resources'/(name+'.tres')).read_text()
        paths=re.findall(r'path="res://([^"\n]+)"',text)
        if len(paths)<2 or 'ManusCC0-' not in paths[0] or paths[1]!=str(FONT.relative_to(ROOT)):
            raise ValueError('ManusCC0 must remain primary with the bounded CJK face after it')
        if 'base_font = ExtResource("1_manuscc0")' not in text or 'fallbacks = Array[Font]([ExtResource("2_cjk")])' not in text:
            raise ValueError('Missing explicit primary/fallback chain')
    if 'allow_system_fallback=false' not in Path(str(FONT)+'.import').read_text():
        raise ValueError('System fallback must be disabled')
    manifest=json.loads(FONT.with_name('cjk-font.json').read_text())
    if manifest['sha256']!=SHA256 or not manifest['subset'] or manifest['bytes']!=len(raw):
        raise ValueError('Stale compact CJK provenance')
    print(f'BOUNDED_CJK_PASS {FONT.relative_to(ROOT)}: {len(raw)} bytes, 6547 codepoints; ManusCC0 primary')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',type=Path,help='Approved ManusGameSC-Common.woff2 to restore')
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    if not args.check and args.source:
        raw=args.source.read_bytes()
        if len(raw)>MAX_BYTES or hashlib.sha256(raw).hexdigest()!=SHA256:
            raise ValueError('Refusing oversized or unapproved CJK font')
        FONT.write_bytes(raw)
    verify()

if __name__=='__main__':main()
