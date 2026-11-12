"""메모 폴더 상태: 파일 수·크기, 목차 빠짐·중복, 끊어진 링크, 머리말 빠짐, 비밀처럼 보이는 문자열."""
import sys, os, re, glob, collections
d = sys.argv[1]
files = sorted(f for f in glob.glob(os.path.join(d, '**', '*.md'), recursive=True))
slugs = {os.path.basename(f)[:-3]: f for f in files}
body = {s: open(f, encoding='utf-8').read() for s, f in slugs.items()}
stubs = [s for s, t in body.items() if t.strip().startswith('MOVED TO')]
live = [s for s in slugs if s != '_index' and s not in stubs]
idx = re.findall(r'\[\[([^\]]+)\]\]', body.get('_index', ''))
cnt = collections.Counter(idx)
nofm = [s for s in live if not body[s].startswith('---\nname:')]
dangling = sorted({(s, l) for s in live + ['_index'] if s in body for l in re.findall(r'\[\[([^\]|#]+)', body[s]) if l not in slugs})
sec = [s for s in live if re.search(r'sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|eyJ[A-Za-z0-9_-]{30,}\.', body[s])]
total = sum(len(body[s].encode()) for s in live)
print(f'live files {len(live)}, stubs {len(stubs)}, bytes {total} ({total/1e3:.0f}KB), biggest {max((len(body[s].encode()), s) for s in live)}')
print(f'_index bytes {len(body.get("_index","").encode())}, entries {len(idx)}, distinct {len(cnt)}, duplicated {[k for k, v in cnt.items() if v > 1]}')
print('live files missing from index:', [s for s in live if s not in cnt])
print('index entries without file or pointing at stub:', [k for k in cnt if k not in slugs or k in stubs])
print('missing frontmatter:', nofm)
print('dangling links:', len(dangling), dangling[:8])
print('secret-like strings in:', sec)
lines = sum(1 for s in live for l in body[s].splitlines() if re.match(r'\s*(-|\d+\.)\s+\S', l))
print('fact lines (bullets):', lines)
