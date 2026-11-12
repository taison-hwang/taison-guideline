"""구성비(어떤 블록이 기록을 차지하는가)와 기억성 쓰기(진행 기록·결정 기록·상태 파일·메모리)를 잰다."""
import json, sys, os, re, glob, collections
proj = sys.argv[1]
comp = collections.Counter(); memw = collections.defaultdict(lambda: [0, 0]); zsh = set(); allsess = 0
trunc = collections.Counter()
def tx(c):
    if isinstance(c, str): return c
    return '\n'.join(b.get('text', '') for b in c or [] if isinstance(b, dict) and b.get('type') == 'text')
def dest(p):
    if '/docs/progress/' in p: return 'docs/progress'
    if 'decisions.tsv' in p: return 'decisions.tsv'
    if '/docs/status/' in p: return 'docs/status(계획·상태판)'
    if '/herdr/handoff/' in p: return 'handoff(상태·보고 파일)'
    if '/memory/' in p and '.claude/projects' in p: return 'Claude 자동 메모리'
    if p.endswith('AGENTS.md') or p.endswith('CLAUDE.md'): return 'AGENTS.md'
    return None
for f in glob.glob(os.path.join(proj, '*.jsonl')):
    uses = {}; hit = False; allsess += 1
    for line in open(f, encoding='utf-8', errors='replace'):
        try: d = json.loads(line)
        except ValueError: continue
        if d.get('type') not in ('user', 'assistant') or d.get('isSidechain'): continue
        c = d.get('message', {}).get('content')
        if isinstance(c, str):
            comp['user 글'] += len(c.encode()); continue
        for b in c or []:
            if not isinstance(b, dict): continue
            t = b.get('type')
            if t == 'text': comp['assistant 글' if d['type'] == 'assistant' else 'user 글'] += len(b.get('text', '').encode())
            elif t == 'tool_use':
                uses[b['id']] = b['name']; inp = b.get('input', {})
                n = len(json.dumps(inp, ensure_ascii=False).encode()); comp['호출 입력:' + b['name']] += n
                if b['name'] in ('Write', 'Edit', 'MultiEdit'):
                    k = dest(inp.get('file_path', ''))
                    if k:
                        memw[k][0] += 1; memw[k][1] += len((inp.get('content') or inp.get('new_string') or '').encode())
                if b['name'] == 'Bash':
                    cmd = inp.get('command', '')
                    m = re.search(r'>>?\s*(\S*(?:docs/progress|decisions\.tsv|herdr/handoff|docs/status)\S*)', cmd)
                    if m:
                        k = dest('/' + m.group(1).lstrip('"\'~')) or 'handoff(상태·보고 파일)'
                        memw[k + ' (셸)'][0] += 1; memw[k + ' (셸)'][1] += len(cmd.encode())
            elif t == 'tool_result':
                body = tx(b.get('content')); n = len(body.encode()); name = uses.get(b.get('tool_use_id'), '?')
                comp['결과:' + name] += n
                trunc['all'] += n; trunc['cap4k'] += min(n, 4096); trunc['cap2k'] += min(n, 2048)
                if re.search(r'=+ not found', body): hit = True
    if hit: zsh.add(f)
tot = sum(comp.values())
print('rendered total MB', tot / 1e6)
for k, v in comp.most_common(16): print(f'{v/1e6:7.2f}MB {v/tot:5.1%}  {k}')
res = sum(v for k, v in comp.items() if k.startswith('결과:'))
print(f'tool results {res/1e6:.1f}MB; capped 4KB each -> {trunc["cap4k"]/1e6:.1f}MB; 2KB -> {trunc["cap2k"]/1e6:.1f}MB')
print(f'rendered with 4KB cap: {(tot-res+trunc["cap4k"])/1e6:.1f}MB, 2KB cap: {(tot-res+trunc["cap2k"])/1e6:.1f}MB')
print('memory-like writes (calls, KB):')
for k, (n, b) in sorted(memw.items(), key=lambda x: -x[1][1]): print(f'  {k}: {n} calls, {b/1e3:.0f}KB')
print('sessions hitting zsh "=== not found":', len(zsh), 'of', allsess)
