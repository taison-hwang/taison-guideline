"""기억성 기록을 누가 읽고 쓰는지 센다(Bash 명령과 Read 호출 기준)."""
import json, sys, os, re, glob, collections, pickle
proj = sys.argv[1]; ss, _, _ = pickle.load(open(sys.argv[2], 'rb')); role = {s['sid']: s['role'] for s in ss}
def grp(r): return 'worker' if r.startswith('worker') else ('verifier' if r.startswith('verif') else (r if r in ('orchestrator',) else '기타'))
T = {'decisions.tsv': r'decisions\.tsv', 'docs/progress': r'docs/progress', 'status-board·work-plan': r'status-board\.md|work-plan\.md',
     'handoff 파일': r'herdr/handoff/', 'Claude 메모리': r'\.claude/projects/[^ ]*/memory/', 'AGENTS.md': r'AGENTS\.md', 'intent.md': r'intent\.md'}
rd = collections.defaultdict(collections.Counter); wr = collections.defaultdict(collections.Counter); rs = collections.defaultdict(set)
for f in glob.glob(os.path.join(proj, '*.jsonl')):
    sid = os.path.basename(f)[:-6]; g = grp(role.get(sid, ''))
    for line in open(f, encoding='utf-8', errors='replace'):
        if '"tool_use"' not in line: continue
        try: d = json.loads(line)
        except ValueError: continue
        if d.get('type') != 'assistant' or d.get('isSidechain'): continue
        for b in d.get('message', {}).get('content') or []:
            if not isinstance(b, dict) or b.get('type') != 'tool_use': continue
            inp = b.get('input') or {}; n = b['name']
            if n == 'Bash':
                cmd = inp.get('command', '')
                for k, pat in T.items():
                    if not re.search(pat, cmd): continue
                    w = re.search(r'(>>?|tee\s+(-a\s+)?)\s*["\']?[^|;&]*(' + pat + ')', cmd) or re.search(r'git (add|commit|mv)|mkdir', cmd) and not re.search(r'\b(cat|grep|rg|tail|head|sed -n|awk|less|wc)\b', cmd)
                    r_ = re.search(r'\b(cat|grep|rg|tail|head|sed -n|awk|less)\b[^|;&>]*(' + pat + ')', cmd)
                    if w: wr[k][g] += 1
                    if r_: rd[k][g] += 1; rs[k].add(sid)
            elif n == 'Read':
                for k, pat in T.items():
                    if re.search(pat, inp.get('file_path', '')): rd[k][g] += 1; rs[k].add(sid)
            elif n in ('Write', 'Edit', 'MultiEdit'):
                for k, pat in T.items():
                    if re.search(pat, inp.get('file_path', '')): wr[k][g] += 1
for k in T:
    print(f'{k}: 읽기 {sum(rd[k].values())}회({len(rs[k])}세션) {dict(rd[k])} | 쓰기 {sum(wr[k].values())}회 {dict(wr[k])}')
