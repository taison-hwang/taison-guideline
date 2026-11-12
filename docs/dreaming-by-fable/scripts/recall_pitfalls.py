"""사람이 손으로 찾아 규칙에 넣은 함정이 메모에 있는지 본다. 패턴마다 걸린 파일 수와 첫 줄을 낸다."""
import sys, os, re, glob
d = sys.argv[1]
KEY = [
 ('R1 sleep 뒤 명령은 도구가 막는다', r'Blocked: sleep|sleep \d+.{0,40}(blocked|막)|sleep.{0,30}(is|was|gets) blocked|Monitor.{0,40}until'),
 ('R2 herdr-report를 뒤에서 돌리면 미보고로 본다', r'herdr-report.{0,80}(background|백그라운드)'),
 ('R2b herdr-report를 timeout으로 감싸면 보고가 죽는다', r'timeout.{0,40}herdr-report|herdr-report.{0,60}timeout'),
 ('R3 상태판 커밋 때문에 ff-only 병합이 자주 실패한다', r'(fast-forward|ff-only).{0,160}(status|상태판|main moved|moved)'),
 ('R3b 병합 출력을 | tail로 넘기면 실패가 가려진다', r'\|\s*tail.{0,120}(mask|hide|hid|swallow|exit|가려|숨)|(mask|hide|hid|swallow).{0,80}\|\s*tail'),
 ('R4 hooksPath·--no-verify로 커밋 검사를 건너뛴다', r'hooksPath|--no-verify'),
 ('P1 ruff 줄 길이에서 한글은 두 칸', r'(E501|line.length|줄 길이|100).{0,80}(Korean|한글|Hangul|wide|두 칸)|(Korean|한글|Hangul).{0,80}(E501|line.length|두 칸|double.width|two col)'),
 ('P2 zsh glob 인자는 따옴표', r'zsh.{0,120}(glob|no matches)|no matches found'),
 ('P2b zsh는 변수를 낱말로 나누지 않는다', r'zsh.{0,120}(word.?split|낱말|array|배열)'),
 ('P3 임시 스크립트에 표준 모듈 이름 금지', r'struct\.py|stdlib module|standard.library module|표준 모듈'),
 ('P3b python -I는 PYTHONPATH를 버린다', r'-I\b.{0,80}PYTHONPATH|PYTHONPATH.{0,80}-I\b'),
 ('P4 mutate-changed는 30~40분 넘게 걸린다', r'mutate-changed.{0,160}(\d+\s*(min|분|m\b)|hour|시간|long|slow|background)'),
 ('P5 macOS sed 차이', r"sed -i ''|BSD sed|macOS.{0,20}sed"),
]
files = [f for f in glob.glob(os.path.join(d, '**', '*.md'), recursive=True)]
for name, pat in KEY:
    hits = []
    for f in files:
        for l in open(f, encoding='utf-8'):
            if re.search(pat, l, re.I): hits.append((os.path.basename(f), l.strip()))
    fs = {h[0] for h in hits}
    print(f'[{"O" if hits else "X"}] {name}: {len(fs)} files')
    for h in hits[:2]: print('     ', h[0], '|', h[1][:260])
