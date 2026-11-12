import sys, os, re, glob, json, random
d, n, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
rows = []
for f in sorted(glob.glob(os.path.join(d, '**', '*.md'), recursive=True)):
    slug = os.path.basename(f)[:-3]
    if slug == '_index': continue
    t = open(f, encoding='utf-8').read()
    if t.strip().startswith('MOVED TO'): continue
    for i, l in enumerate(t.splitlines(), 1):
        if re.match(r'\s*(-|\d+\.)\s+\S', l) and len(l.strip()) >= 50:
            rows.append({'file': slug, 'line': i, 'text': l.strip()[:700]})
random.seed(20261111); random.shuffle(rows)
pick = sorted(rows[:n], key=lambda r: (r['file'], r['line']))
for i, r in enumerate(pick, 1): r['id'] = i
json.dump(pick, open(out, 'w'), ensure_ascii=False, indent=1)
print(len(rows), 'fact lines total; sampled', len(pick))
