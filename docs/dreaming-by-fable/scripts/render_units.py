"""Claude Code 대화 기록(jsonl)을 dreaming 예제의 평문 형식으로 바꾸고, [배정] 경계로 작업 단위로 자른다.
도구 입력·결과는 길면 앞뒤만 남긴다. usage: render.py <jsonl> <outdir> <role> [cap]"""
import json, sys, os, re
src, outdir, role = sys.argv[1], sys.argv[2], sys.argv[3]
CAP = int(sys.argv[4]) if len(sys.argv) > 4 else 3500
MAXUNIT = 260_000
def cap(s, n=CAP):
    if len(s) <= n: return s
    return s[: n * 2 // 3] + f'\n[... {len(s) - n} chars cut ...]\n' + s[-n // 3:]
def tx(c):
    if isinstance(c, str): return c
    return '\n'.join(b.get('text', '') for b in c or [] if isinstance(b, dict) and b.get('type') == 'text')
def guard(s):  # 본문 줄이 라벨처럼 보이지 않게 한 칸 들여 쓴다(예제 형식 규칙)
    return re.sub(r'^(USER:|AGENT:|TOOL CALL|TOOL RESULT|SESSION|===|NOTE ABOUT)', r' \1', s, flags=re.M)
blocks = []; uses = {}; created = ''
for line in open(src, encoding='utf-8', errors='replace'):
    try: d = json.loads(line)
    except ValueError: continue
    if d.get('type') not in ('user', 'assistant') or d.get('isSidechain'): continue
    created = created or d.get('timestamp', '')
    c = d.get('message', {}).get('content')
    if d['type'] == 'user' and isinstance(c, str):
        if c.strip(): blocks.append(('USER', 'USER:\n' + guard(cap(c, 12000)), d.get('timestamp', '')))
        continue
    for b in c or []:
        if not isinstance(b, dict): continue
        t = b.get('type')
        if t == 'text' and b.get('text', '').strip():
            blocks.append(('USER' if d['type'] == 'user' else 'AGENT', ('USER:\n' if d['type'] == 'user' else 'AGENT:\n') + guard(cap(b['text'], 12000)), d.get('timestamp', '')))
        elif t == 'tool_use':
            uses[b['id']] = b['name']
            fields = '\n'.join(f'{k}: ' + ('\n' if '\n' in str(v) else '') + guard(cap(str(v))) for k, v in (b.get('input') or {}).items())
            blocks.append(('CALL', f'TOOL CALL {b["name"]}:\n{fields}', d.get('timestamp', '')))
        elif t == 'tool_result':
            name = uses.get(b.get('tool_use_id'), '?'); body = tx(b.get('content'))
            err = ' [error]' if b.get('is_error') else ''
            blocks.append(('RESULT', f'TOOL RESULT ({name}){err}:\n' + guard(cap(body)), d.get('timestamp', '')))
sid = os.path.basename(src)[:-6]
units = []; cur = []; cur_name = 'start'; size = 0
def flush():
    global cur, size
    if cur: units.append((cur_name, cur))
    cur = []; size = 0
for kind, text, ts in blocks:
    m = re.search(r'\[배정\]\s+(?:Orchestrator\s+\S+\s*→\s*\S+\s*:?\s*)?(.{0,400})', text) if kind == 'USER' else None
    if m and size > 6000:
        flush()
    if m:
        t = re.search(r'작업\s+([A-Za-z0-9][A-Za-z0-9._-]+)|([A-Z][A-Z0-9]+(?:-[A-Za-z0-9]+)+)', m.group(0))
        cur_name = (t.group(1) or t.group(2)) if t else 'task'
    if size + len(text.encode()) > MAXUNIT and kind in ('USER', 'AGENT') and size > 40000:
        flush(); cur_name = cur_name.split('~')[0] + '~cont'
    cur.append(text); size += len(text.encode()) + 2
flush()
os.makedirs(outdir, exist_ok=True)
for i, (name, bl) in enumerate(units):
    safe = re.sub(r'[^A-Za-z0-9._~-]', '_', name)[:40]
    fn = f'{created[:10]}_{role}_{sid[:8]}_{i:02d}_{safe}.txt'
    head = f'SESSION {sid} title="{role} 세션의 작업 단위 {i+1}/{len(units)}: {name}" agent={role} created={created}\n' \
           f'NOTE ABOUT THIS FILE: herdr 하네스 세션(Claude Code) 기록을 작업 단위로 자른 것이다. 긴 도구 입력·결과는 가운데를 잘랐다.\n' \
           f'=== primary thread {sid[:8]}: {role} ===\n\n'
    open(os.path.join(outdir, fn), 'w', encoding='utf-8').write(head + '\n\n'.join(bl) + '\n')
    print(fn, os.path.getsize(os.path.join(outdir, fn)))
