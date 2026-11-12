"""jobtailor 대화 기록을 훑어 세션별 통계와 오류 서명을 뽑는다. 읽기만 한다."""
import json, sys, os, re, glob, collections, pickle
proj, out = sys.argv[1], sys.argv[2]
ROLE = re.compile(r'역할은\s*([A-Za-z0-9_-]+)|role=([A-Za-z0-9_-]+)')
def text_of(content):
    if isinstance(content, str): return content
    parts = []
    for b in content or []:
        if not isinstance(b, dict): continue
        t = b.get('type')
        if t == 'text': parts.append(b.get('text', ''))
        elif t == 'tool_use': parts.append(json.dumps(b.get('input', {}), ensure_ascii=False))
        elif t == 'tool_result': parts.append(text_of(b.get('content')))
    return '\n'.join(parts)
def norm(line):
    line = re.sub(r'/[\w./@+-]{6,}', 'P', line)
    line = re.sub(r'\b[0-9a-f]{7,40}\b', 'H', line)
    line = re.sub(r'\d+', 'N', line)
    return line.strip()[:160]
sessions = []; errs = collections.defaultdict(lambda: collections.defaultdict(int)); errday = {}
for f in sorted(glob.glob(os.path.join(proj, '*.jsonl'))):
    s = dict(sid=os.path.basename(f)[:-6], bytes=os.path.getsize(f), role='', start='', end='', amsg=set(), tools=0, terr=0,
             render=0, peak=0, compacts=0, cost=0.0, model=collections.Counter(), turns=0, tooluse={})
    for line in open(f, encoding='utf-8', errors='replace'):
        try: d = json.loads(line)
        except ValueError: continue
        ts = d.get('timestamp')
        if ts and isinstance(ts, str):
            s['start'] = s['start'] or ts; s['end'] = ts
        t = d.get('type')
        if t == 'cost-state': s['cost'] = d.get('totalCostUSD', 0.0)
        if t == 'system' and d.get('subtype') == 'compact_boundary': s['compacts'] += 1
        if t == 'attachment':
            a = d.get('attachment', {})
            if a.get('type') == 'hook_additional_context' and not s['role']:
                c = a.get('content'); c = ' '.join(c) if isinstance(c, list) else str(c)
                m = ROLE.search(c)
                if m and '[herdr 역할]' in c: s['role'] = m.group(1) or m.group(2)
            continue
        if t not in ('user', 'assistant') or d.get('isSidechain'): continue
        msg = d.get('message', {}); content = msg.get('content')
        if t == 'assistant':
            mid = msg.get('id')
            u = msg.get('usage') or {}
            ctx = (u.get('input_tokens') or 0) + (u.get('cache_read_input_tokens') or 0) + (u.get('cache_creation_input_tokens') or 0)
            s['peak'] = max(s['peak'], ctx)
            if mid not in s['amsg']:
                s['amsg'].add(mid); s['model'][msg.get('model', '')] += 1
            for b in content or []:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    s['tools'] += 1; s['tooluse'][b.get('id')] = b.get('name')
            s['render'] += len(text_of(content).encode())
        else:
            if isinstance(content, str):
                s['turns'] += 1
                if not s['role']:
                    m = ROLE.search(content[:3000])
                    if m: s['role'] = m.group(1) or m.group(2)
            s['render'] += len(text_of(content).encode())
            for b in content if isinstance(content, list) else []:
                if isinstance(b, dict) and b.get('type') == 'tool_result':
                    body = text_of(b.get('content'))
                    bad = b.get('is_error') or re.search(r'^Exit code [1-9]', body, re.M)
                    if not bad: continue
                    s['terr'] += 1
                    name = s['tooluse'].get(b.get('tool_use_id'), '?')
                    lines = [l for l in body.splitlines() if l.strip() and not l.startswith('Exit code')]
                    key = [l for l in lines if re.search(r'rror|FAIL|fatal|denied|not found|No such|cannot|Cannot|refus|거부|실패|없|막', l)]
                    sig = name + ': ' + norm((key or lines or ['(empty)'])[0])
                    errs[sig][s['sid']] += 1
                    errday.setdefault(sig, set()).add((s['start'] or '')[:10])
    s['amsg'] = len(s['amsg']); s['model'] = s['model'].most_common(1)[0][0] if s['model'] else ''; del s['tooluse']
    sessions.append(s)
pickle.dump((sessions, {k: dict(v) for k, v in errs.items()}, errday), open(out, 'wb'))
print(len(sessions), 'sessions scanned')
