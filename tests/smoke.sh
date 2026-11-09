#!/usr/bin/env bash
# 하네스 설치·hook·실행기의 기계적 동작을 확인한다. 전역과 실제 세션을 건드리지 않는다.
# 사용: tests/smoke.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); }
no() { fail=$((fail + 1)); echo "실패: $1"; }
check() { if eval "$2"; then ok; else no "$1"; fi; }
# sed -i는 GNU와 BSD(macOS)의 인자가 달라 임시 파일로 바꾼다.
set_env() { sed "$1" "$2" >"$2.tmp" && mv "$2.tmp" "$2"; }

P="$WORK/demo"
"$ROOT/bin/harness" init "$P" >/dev/null

echo "== 설치"
for f in AGENTS.md CLAUDE.md intent.md .gitignore .agents/harness.env .claude/settings.json .codex/hooks.json docs/status/work-plan.md docs/status/decisions.tsv .agents/bin/herdr-session .agents/bin/herdr-view .agents/bin/herdr-check .agents/hooks/check-edit.sh .agents/hooks/context-signal.sh .agents/skills/running-herdr-autopilot/SKILL.md .agents/skills/implementing-with-tdd/SKILL.md .agents/skills/writing-project-docs/scripts/check_md_links.py; do
  check "파일 없음: $f" "[ -e '$P/$f' ]"
done
check "skills 링크" "[ \"\$(readlink '$P/.claude/skills')\" = ../.agents/skills ]"
check "프로젝트 이름 치환" "grep -q '에이전트 지침 — demo' '$P/AGENTS.md'"
check "블록 삽입" "grep -q 'running-herdr-autopilot' '$P/AGENTS.md'"
check "확인 규칙이 항상 적용 지침에 있음" "grep -q '주석, 문서, 보고, 요약은 단서다' '$P/AGENTS.md'"
check "결정 기록 머리글" "[ \"\$(head -n 1 '$P/docs/status/decisions.tsv' | awk -F'\t' '{print NF}')\" = 6 ]"
check "작업 계획에 시작 계약" "grep -q '완료 조건' '$P/docs/status/work-plan.md'"
W_REF="$P/.agents/skills/running-herdr-autopilot/references/worker.md"
O_REF="$P/.agents/skills/running-herdr-autopilot/references/orchestrator.md"
C_REF="$P/.agents/skills/managing-session-context/SKILL.md"
check "검증자는 분리된 worktree에서 실행" "grep -q 'git worktree add --detach' '$W_REF'"
check "검증자는 분기점 기준으로 범위 확인" "grep -qF 'git diff <분기점 SHA> <head SHA>' '$W_REF'"
check "검증자는 판정으로 보고" "grep -qF '[판정] <묶음> PASS|ISSUES|BLOCKED' '$W_REF'"
check "rebase에서 코드가 바뀌면 병합 중단" "grep -q '충돌 해결이나 코드 수정이 생기면 병합하지 않고' '$W_REF'"
check "PASS 없이 병합 금지" "grep -qF '\`PASS\` 없이 \`[병합]\`을 보내지 않는다' '$O_REF'"
check "판정을 직접 뒤집지 않음" "grep -q '판정을 직접 뒤집지 않는다' '$O_REF'"
check "BLOCKED는 축소 조건에서 제외" "grep -qF '\`BLOCKED\`는 세지 않는다' '$O_REF'"
check "첫 묶음은 첫 [완료] 수용까지만 먼저" "grep -qF '첫 \`[완료]\`를 수용 기준과 대조해 받아들인 뒤 나머지 코드 묶음을 배정한다' '$O_REF'"
check "코드 안 바꾸는 작업은 처음부터 병행" "grep -q '코드를 바꾸지 않는 작업(조사, 스펙, 문서)은 처음부터' '$O_REF'"
check "첫 묶음 병합까지 기다리는 규칙 없음" "! grep -qE '병합까지 통과시킨다|첫 묶음이 병합까지 통과한 뒤' '$O_REF'"
check "독립 검증은 검사를 기다리지 않고 배정" "grep -q '검사 결과를 기다리지 않고 독립 검증을 배정할 수 있다' '$O_REF'"
check "병합은 같은 SHA의 검사 PASS와 판정 PASS 둘 다" "grep -qF '같은 SHA에 \`검사 PASS\`와 판정 \`PASS\`가 모두 있을 때만' '$O_REF'"
check "워커는 긴 검사 전에 커밋 SHA와 예상 시간을 알림" "grep -qF '[진행] <작업 ID> 커밋 <SHA> 검사 중 예상 <소요 시간>' '$W_REF'"
check "사용자 결정은 그 단계만 막음" "grep -q '그 결정이 필요한 단계만 막는다' '$O_REF' && grep -q '그 결정이 필요한 단계만 막는다' '$P/.agents/skills/running-herdr-autopilot/SKILL.md'"
check "결정을 대신 내리지 않음" "grep -q '결정을 가정해 병합하지 않는다' '$O_REF'"
check "대기 표에 만료" "grep -qF '| 작업 ID | 기다리는 것 | 시작 | 풀릴 조건 | 만료 | 만료 시 |' '$P/docs/status/status-board.md'"
check "만료된 대기 처리 순서" "grep -q '만료가 지난 대기' '$O_REF' && grep -q '병행 착수' '$O_REF'"
check "만료는 소요 시간을 예측한 뒤 정함" "grep -q '소요 시간을 예측한 뒤' '$O_REF' && ! grep -q '기본 30분' '$O_REF'"
check "만료되면 진행부터 확인하고 진행 중이면 늘림" "grep -q '정상으로 진행 중이면 남은 시간을 다시 예측해' '$O_REF'"
check "진행을 확인한 연장은 세지 않음" "grep -q '진행을 확인하지 못한 채 두 번 늘렸으면' '$O_REF'"
check "의존 대기는 만료돼도 다른 세션에 넘기지 않음" "grep -q '1행(의존) 대기는 다른 세션에 넘기지 않는다' '$O_REF'"
check "연관 없는 작업은 정리 후 배정" "grep -qF '| 연관 없음 | 정리 후 배정 |' '$C_REF'"
check "연관 작업은 맥락 크기와 무관하게 이어 감" "grep -q '맥락 크기와 compact 횟수는 보지 않는다' '$C_REF'"
check "처리 중인 작업은 끝까지" "grep -q '처리 중인 작업은 끝까지 하고' '$C_REF'"
check "옛 CLEAR 조건이 규칙에 없음" "! grep -rq 'CLEAR 조건' '$P/.agents/skills' '$P/.agents/hooks'"
check "크기로 정리를 정하는 규칙 없음" "! grep -qE '작은 일|큰 일|작은 후속|큰 작업은 정리' '$C_REF' '$O_REF'"
check "compact 이력으로 연관도를 낮추지 않음" "! grep -q '연관도를 한 단계 낮게' '$O_REF'"
check "연관도는 현재 작업과 맥락을 함께 봄" "grep -qF '\"현재 작업\" 칸과 \"맥락\" 칸에 비교' '$O_REF'"
check "바쁜 연관 세션은 예약" "grep -q '그 세션. 바쁘면 다음 예약에 적는다' '$O_REF'"
check "빈 세션은 연관 세션이 없을 때만" "grep -qF '| 3 | 연관 높은 세션이 없고,' '$O_REF'"
check "장부에 다음 예약 칸" "grep -q '| 다음 예약 |' '$O_REF'"
check "첫 완료만으로 정리하지 않음" "grep -q '첫 \`\[완료\]\`만으로는 정리하지 않는다' '$C_REF'"
check "CLEAR 요청의 두 경로" "grep -q '소프트 신호에 따른 자기 정리 요청' '$P/.agents/skills/running-herdr-autopilot/SKILL.md'"
check "검증자 역할은 워커로 처리" "'$P/.agents/bin/herdr-session' --dry-run verifier-1 codex | grep -q 'gpt-6.1-sol'"
check "worktree ignore" "grep -qxF '/docs/.worktrees/' '$P/.gitignore'"
check "graft 파일 ignore" "grep -qxF /graft/ '$P/.gitignore' && grep -qxF /.ignore '$P/.gitignore'"
check "설정 JSON" "jq -e .hooks.PreCompact '$P/.claude/settings.json' >/dev/null && jq -e .hooks.SessionStart '$P/.codex/hooks.json' >/dev/null"

echo "== 갱신은 프로젝트 내용을 보존"
echo '- 고유 규칙 ABC' >>"$P/AGENTS.md"
echo 'HERDR_MAX_WORKERS=9' >>"$P/.agents/harness.env"
mkdir -p "$P/.agents/skills/my-own"; echo x >"$P/.agents/skills/my-own/SKILL.md"
"$ROOT/bin/harness" sync "$P" >/dev/null
"$ROOT/bin/harness" sync "$P" >/dev/null
check "고유 규칙 유지" "grep -q '고유 규칙 ABC' '$P/AGENTS.md'"
check "블록 중복 없음" "[ \"\$(grep -c '하네스 기본 규칙' '$P/AGENTS.md')\" = 1 ]"
check "환경 값 유지" "grep -q 'HERDR_MAX_WORKERS=9' '$P/.agents/harness.env'"
check "전용 스킬 유지" "[ -f '$P/.agents/skills/my-own/SKILL.md' ]"

echo "== 새 설정 칸은 sync가 끝에 추가"
E="$P/.agents/harness.env"
set_env '/^HERDR_MAX_VERIFIERS=/d; /^HERDR_CHECK_SKIP_PATHS=/d; s/^HERDR_CHECK_TIMEOUT=.*/HERDR_CHECK_TIMEOUT=1800/' "$E"
out="$("$ROOT/bin/harness" sync "$P")"
"$ROOT/bin/harness" sync "$P" >/dev/null
check "빠진 설정을 기본값으로 추가" "grep -qx 'HERDR_MAX_VERIFIERS=1' '$E' && grep -qx 'HERDR_CHECK_SKIP_PATHS=' '$E'"
check "추가한 설정의 설명도 함께" "grep -B1 -x 'HERDR_MAX_VERIFIERS=1' '$E' | grep -q '독립 검증자 수' && grep -B1 -x 'HERDR_CHECK_SKIP_PATHS=' '$E' | grep -q '예: HERDR_CHECK_SKIP_PATHS'"
check "있는 값은 바꾸지 않음" "grep -qx 'HERDR_CHECK_TIMEOUT=1800' '$E' && [ \"\$(grep -c '^HERDR_CHECK_TIMEOUT=' '$E')\" = 1 ]"
check "다시 sync해도 중복 없음" "[ \"\$(grep -c '^HERDR_MAX_VERIFIERS=' '$E')\" = 1 ] && [ \"\$(grep -c '^HERDR_CHECK_SKIP_PATHS=' '$E')\" = 1 ]"
check "추가한 칸을 알림" "printf '%s' \"\$out\" | grep -q 'harness.env에 새 설정 추가: HERDR_MAX_VERIFIERS HERDR_CHECK_SKIP_PATHS'"
set_env 's/^HERDR_CHECK_TIMEOUT=.*/HERDR_CHECK_TIMEOUT=3600/' "$E"

echo "== 기존 프로젝트 보호"
Q="$WORK/existing"; mkdir -p "$Q/.agents/skills/writing-project-docs"; echo mine >"$Q/.agents/skills/writing-project-docs/SKILL.md"
check "같은 이름 스킬이면 init 중단" "! '$ROOT/bin/harness' init '$Q' >/dev/null 2>&1"
check "그 스킬을 덮어쓰지 않음" "grep -qx mine '$Q/.agents/skills/writing-project-docs/SKILL.md'"
check "미설치 폴더 sync 거부" "! '$ROOT/bin/harness' sync '$Q' >/dev/null 2>&1"

echo "== 소프트 신호"
export HOME="$WORK/home"; mkdir -p "$HOME"
H="$P/.agents/hooks/context-signal.sh"
T="$WORK/t.jsonl"
usage() { printf '{"type":"assistant","message":{"usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' "$1" >"$T"; }
fire() { printf '{"session_id":"s1","transcript_path":"%s","hook_event_name":"PostToolUse"}' "$T" | HERDR_ROLE="${1:-worker-1}" "$H"; }
usage 299000; check "임계 미만 무출력" "[ -z \"\$(fire)\" ]"
usage 300000; out="$(fire)"
check "임계에서 알림" "printf '%s' \"\$out\" | jq -e '.hookSpecificOutput.additionalContext | test(\"소프트 신호 300k\")' >/dev/null"
check "워커에 계속 진행 안내" "printf '%s' \"\$out\" | grep -q '수용 기준까지 계속한다'"
check "워커에 /clear 요청 금지 안내" "printf '%s' \"\$out\" | grep -q '/clear를 요청하지 않는다'"
check "워커에 마무리 지시 없음" "! printf '%s' \"\$out\" | grep -q '커밋 가능한 지점'"
check "워커 신호로 새 작업을 막지 않음" "! printf '%s' \"\$out\" | grep -q '새 작업'"
usage 350000; check "간격 안에서 재알림 없음" "[ -z \"\$(fire)\" ]"
usage 400000; check "간격을 넘으면 재알림" "[ -n \"\$(fire)\" ]"
usage 100000; fire >/dev/null; usage 310000
check "compact로 내려간 뒤 다시 알림" "[ -n \"\$(fire)\" ]"
rm -f "$HOME/.claude/herdr/ctx-signal/s1"; usage 300000
orch="$(fire orchestrator)"
check "Orchestrator 문구" "printf '%s' \"\$orch\" | grep -q 'CLEAR 요청'"
check "Orchestrator에 새 배정 보류 안내" "printf '%s' \"\$orch\" | grep -q '새 배정은 정리 뒤로'"
check "role 없으면 무출력" "[ -z \"\$(printf '{\"session_id\":\"s2\",\"transcript_path\":\"$T\"}' | env -u HERDR_ROLE '$H')\" ]"

echo "== compact 복구"
export HERDR_ROLE=worker-1 HERDR_PROJECT=demo
D="$HOME/.claude/herdr/handoff/demo"; mkdir -p "$D"
seq 1 100 | sed 's/^/상태 /' >"$D/worker-1.md"
pre="$(printf '{"cwd":"%s"}' "$P" | "$P/.agents/hooks/pre-compact.sh")"
check "요약 지시 출력" "printf '%s' \"\$pre\" | grep -q '수용 기준'"
check "스냅샷 저장" "grep -q '브랜치:' '$D/worker-1.snapshot.md'"
res="$(echo '{"source":"compact"}' | "$P/.agents/hooks/session-start.sh" | jq -r '.hookSpecificOutput.additionalContext')"
check "복구 주입" "printf '%s' \"\$res\" | grep -q 'compact 복구' && printf '%s' \"\$res\" | grep -q '상태 40'"
check "compact 복구가 새 작업이나 정리를 지시하지 않음" "! printf '%s' \"\$res\" | grep -qE '새 작업|CLEAR 요청'"
check "상태 길이 제한" "! printf '%s' \"\$res\" | grep -q '상태 41'"
check "compact 횟수 누적" "[ \"\$(cat '$D/.worker-1.compacts')\" = 1 ]"
boot="$(echo '{"source":"clear"}' | "$P/.agents/hooks/session-start.sh" | jq -r '.hookSpecificOutput.additionalContext')"
check "clear 뒤 역할과 경로 주입" "printf '%s' \"\$boot\" | grep -q 'references/worker.md' && printf '%s' \"\$boot\" | grep -q 'operating-herdr-sessions'"
check "clear 뒤에는 상태 파일을 넣지 않음" "! printf '%s' \"\$boot\" | grep -q '상태 1'"
check "clear로 compact 횟수 초기화" "[ ! -f '$D/.worker-1.compacts' ]"
check "Orchestrator 역할 파일 안내" "echo '{\"source\":\"startup\"}' | HERDR_ROLE=orchestrator '$P/.agents/hooks/session-start.sh' | grep -q 'references/orchestrator.md'"
rm "$D/worker-1.md"
res="$(echo '{"source":"compact"}' | "$P/.agents/hooks/session-start.sh" | jq -r '.hookSpecificOutput.additionalContext')"
check "상태 파일 없을 때 안내" "printf '%s' \"\$res\" | grep -q '상태 파일 없음'"
unset HERDR_ROLE HERDR_PROJECT

echo "== 보고와 보고 누락 방지"
mkdir -p "$WORK/stub2"
cat >"$WORK/stub2/hc" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$WORK/hc.log"
case "\$1" in
  ls) case "\$*" in *role=orchestrator*) echo '{"terminals":[{"address":"t9"}]}' ;; *) echo '{"terminals":[]}' ;; esac ;;
  get) echo '{}' ;;
esac
EOF
chmod +x "$WORK/stub2/hc"
export HERDR_ROLE=worker-1 HERDR_PROJECT=demo
oldpath="$PATH"; export PATH="$WORK/stub2:$PATH"
R="$P/.agents/bin/herdr-report"; TURN="$P/.agents/hooks/worker-turn.sh"; D="$HOME/.claude/herdr/handoff/demo"
rm -f "$D/.worker-1.reported" "$D/.worker-1.turn-start"
check "턴 기록 없으면 막지 않음" "[ -z \"\$(echo '{}' | '$TURN' stop)\" ]"
echo '{}' | "$TURN" start
check "보고 없으면 턴 종료를 막음" "echo '{}' | '$TURN' stop | jq -e '.decision == \"block\"' >/dev/null"
check "한 번 막힌 뒤에는 Orchestrator에 미보고 전달" "[ -z \"\$(echo '{\"stop_hook_active\":true}' | '$TURN' stop)\" ] && grep -q 'send t9 \\[미보고\\] worker-1' '$WORK/hc.log'"
check "미보고 전달 뒤에는 더 막지 않음" "[ -z \"\$(echo '{}' | '$TURN' stop)\" ]"
sleep_until_next_second() { local n; n=$(date +%s); while [ "$(date +%s)" = "$n" ]; do :; done; }
sleep_until_next_second
echo '{}' | "$TURN" start
check "다음 턴에는 다시 막음" "echo '{}' | '$TURN' stop | jq -e .decision >/dev/null"
G="$WORK/repo"; git init -q -b main "$G"; git -C "$G" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cd "$G"
"$R" "[완료] A-01 요약" >/dev/null
check "보고가 Orchestrator로 감" "grep -q 'send t9 \\[완료\\] A-01' '$WORK/hc.log'"
rm -f "$D/.worker-1.compacts"; echo 123456 >"$D/.worker-1.ctx"; "$R" "[진행] x" >/dev/null
check "보고에 맥락 크기 자동 첨부" "grep -q 'ctx 123k · compact 0' '$WORK/hc.log'"
check "보고하면 막지 않음" "[ -z \"\$(echo '{}' | '$TURN' stop)\" ]"
check "Orchestrator·Commander는 막지 않음" "[ -z \"\$(echo '{}' | HERDR_ROLE=orchestrator '$TURN' stop)\" ]"
: >"$WORK/hc.log"
check "보고 대상 없으면 실패" "! HERDR_ROLE=orchestrator '$R' '[완료] x' >/dev/null 2>&1"

echo "== 검사 관문"
C="$P/.agents/bin/herdr-check"; E="$P/.agents/hooks/check-edit.sh"
commit_all() { git -C "$G" add -A && git -C "$G" -c user.email=t@t -c user.name=t commit -q -m "$1"; }
: >"$WORK/hc.log"; "$R" "[완료] A-02 x" >/dev/null 2>&1
check "검사 명령이 없으면 막지 않고 미설정 표시" "grep -q 'send t9 \[완료\] A-02 x · 검사 미설정' '$WORK/hc.log'"
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD="echo run >>count.log; test ! -e fail.flag"/' "$P/.agents/harness.env"
echo count.log >"$G/.gitignore"; commit_all ignore
check "기록이 없으면 오류 없이 NONE" "[ \"\$(HERDR_ROLE=never-checked '$C' --status 2>&1)\" = NONE ]"
git -C "$G" worktree add -q "$WORK/repo-wt" -b wt
cd "$WORK/repo-wt"; echo x >a.txt; : >"$WORK/hc.log"
check "worktree에 커밋 안 된 변경이 있으면 [완료]를 막음" "! '$R' '[완료] A-03 x' >/dev/null 2>&1 && ! grep -q 'A-03' '$WORK/hc.log'"
check "[진행]은 커밋 안 된 변경이 있어도 보냄" "'$R' '[진행] A-03 x' >/dev/null 2>&1 && grep -q 'A-03' '$WORK/hc.log'"
rm -f a.txt; cd "$G"; git -C "$G" worktree remove "$WORK/repo-wt"
echo x >"$G/a.txt"; : >"$WORK/hc.log"
check "메인 체크아웃의 [완료]는 커밋 안 된 변경이 있어도 검사 후 보냄" "'$R' '[완료] A-03m x' >/dev/null 2>&1 && grep -q 'A-03m x · 검사 PASS' '$WORK/hc.log'"
commit_all a; : >"$WORK/hc.log"; rm -f "$G/count.log"
"$R" "[완료] A-04 x" >/dev/null 2>&1
check "검사 통과하면 SHA를 붙여 보냄" "grep -q \"send t9 \\[완료\\] A-04 x · 검사 PASS \$(git -C '$G' rev-parse HEAD)\" '$WORK/hc.log'"
touch "$G/fail.flag"; commit_all fail; : >"$WORK/hc.log"
check "검사 실패하면 [완료]를 막음" "! '$R' '[완료] A-05 x' >/dev/null 2>&1 && ! grep -q 'A-05' '$WORK/hc.log'"
check "실패 기록" "'$C' --status | grep -q '^FAIL '"
git -C "$G" rm -q fail.flag; commit_all fix; rm -f "$G/count.log"
"$C" >/dev/null 2>&1; "$R" "[완료] A-06 x" >/dev/null 2>&1
check "같은 HEAD에서 통과한 기록이 있으면 다시 돌리지 않음" "[ \"\$(wc -l <'$G/count.log')\" -eq 1 ] && grep -q 'A-06 x · 검사 PASS' '$WORK/hc.log'"
check "Orchestrator의 [완료]는 관문을 거치지 않음" "touch '$G/dirty.txt'; HERDR_ROLE=orchestrator '$R' '[완료] x' >/dev/null 2>&1; rm -f '$G/dirty.txt'; ! grep -q 'run' '$WORK/hc.log'"
cd "$ROOT"

echo BAD >"$G/bad.txt"; echo ok >"$G/ok.txt"
check "빠른 검사 명령이 없으면 편집 hook은 통과" "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$G/bad.txt\"}}' | '$E'"
set_env 's/^HERDR_CHECK_FILE_CMD=.*/HERDR_CHECK_FILE_CMD="! grep -n BAD {files}"/' "$P/.agents/harness.env"
check "Claude 편집: 문제 없으면 통과" "echo '{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$G/ok.txt\"}}' | '$E'"
out="$(echo "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$G/bad.txt\"}}" | "$E" 2>&1)"; rc=$?
check "Claude 편집: 실패하면 끝 코드 2와 출력" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q 'bad.txt' && printf '%s' \"\$out\" | grep -q '1:BAD'"
patch='*** Begin Patch\n*** Update File: bad.txt\n@@\n-x\n+BAD\n*** Delete File: gone.txt\n*** End Patch'
out="$(printf '{"tool_name":"apply_patch","cwd":"%s","tool_input":{"command":"%s"}}' "$G" "$patch" | "$E" 2>&1)"; rc=$?
check "Codex apply_patch: 상대 경로를 cwd 기준으로 검사" "[ $rc -eq 2 ] && printf '%s' \"\$out\" | grep -q 'bad.txt'"
out="$(printf '{"tool_name":"apply_patch","cwd":"%s","tool_input":{"command":["apply_patch","%s"]}}' "$G" "$patch" | "$E" 2>&1)"; rc=$?
check "Codex apply_patch: command 배열도 읽음" "[ $rc -eq 2 ]"
check "Codex apply_patch: 문제 없는 파일은 통과" "printf '{\"tool_name\":\"apply_patch\",\"cwd\":\"%s\",\"tool_input\":{\"command\":\"*** Begin Patch\\\\n*** Add File: ok.txt\\\\n*** End Patch\"}}' '$G' | '$E'"
check "Orchestrator 편집은 검사하지 않음" "echo '{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$G/bad.txt\"}}' | HERDR_ROLE=orchestrator '$E'"
check "다른 도구는 검사하지 않음" "echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}' | '$E'"
check "hook 설정: Claude 편집 matcher" "jq -e '.hooks.PostToolUse[] | select(.matcher == \"Edit|Write|MultiEdit|NotebookEdit\")' '$P/.claude/settings.json' >/dev/null"
check "hook 설정: Codex apply_patch matcher" "jq -e '.hooks.PostToolUse[] | select(.matcher == \"^apply_patch\$\")' '$P/.codex/hooks.json' >/dev/null"
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD=/; s/^HERDR_CHECK_FILE_CMD=.*/HERDR_CHECK_FILE_CMD=/' "$P/.agents/harness.env"
rm -f "$D/.worker-1.check" "$D/.worker-1.check.log"
export PATH="$oldpath"; unset HERDR_ROLE HERDR_PROJECT

echo "== 사용량 기록과 집계"
D="$HOME/.claude/herdr/handoff/demo"; SS="$P/.agents/hooks/session-start.sh"; U="$P/.agents/bin/herdr-usage"
rm -f "$D/sessions.tsv" "$D/reports.tsv"
CL="$WORK/cl"; mkdir -p "$CL/s-claude/subagents"
# Claude: 응답 하나가 content block마다 같은 usage를 반복 기록한다(m1 두 줄).
cl_line() { printf '{"type":"assistant","timestamp":"%s","sessionId":"s-claude","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_creation":{"ephemeral_5m_input_tokens":%s,"ephemeral_1h_input_tokens":%s},"cache_read_input_tokens":%s}}}\n' "$@"; }
{
  cl_line 2026-11-09T01:00:00.000Z m1 claude-opus-5-5 10 100 1000 0 1000 5000
  cl_line 2026-11-09T01:00:00.000Z m1 claude-opus-5-5 10 100 1000 0 1000 5000
  echo '{"type":"user","timestamp":"2026-11-09T01:05:00.000Z","message":{"content":"x"}}'
  cl_line 2026-11-09T03:00:00.000Z m2 claude-opus-5-5 1 50 0 0 0 2000
} >"$CL/s-claude.jsonl"
cl_line 2026-11-09T01:30:00.000Z m3 claude-sonnet-5-5 2 20 300 300 0 100 >"$CL/s-claude/subagents/agent-a.jsonl"
# Codex: rollout 이름 끝이 session_id다. usage 레코드에는 모델이 없어 turn_context에서 읽는다.
CX="$HOME/.codex/sessions/2026/11/09"; mkdir -p "$CX"
cx_line() { printf '{"timestamp":"%s","type":"token_usage_record","payload":{"session_id":"cx1","response_id":"%s","usage":{"input_tokens":%s,"cached_input_tokens":%s,"cache_write_input_tokens":0,"output_tokens":%s,"reasoning_output_tokens":0,"total_tokens":0}}}\n' "$@"; }
{
  echo '{"timestamp":"2026-11-09T01:00:00.000Z","type":"session_meta","payload":{"id":"cx1","cwd":"/x"}}'
  echo '{"timestamp":"2026-11-09T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-6.1-sol"}}'
  cx_line 2026-11-09T01:10:00.000Z r1 1000 800 30
  cx_line 2026-11-09T01:10:00.000Z r1 1000 800 30
  cx_line 2026-11-09T02:00:00.000Z r2 500 400 10
} >"$CX/rollout-2026-11-09T10-00-00-cx1.jsonl"
start() { printf '{"session_id":"%s","transcript_path":%s,"source":"%s","model":"m"}' "$3" "$4" "$5" | HERDR_ROLE="$1" HERDR_TOOL="$2" HERDR_PROJECT=demo "$SS"; }
out="$(start worker-1 claude s-claude "\"$CL/s-claude.jsonl\"" startup)"
check "장부를 남겨도 hook 출력은 JSON" "printf '%s' \"\$out\" | jq -e .hookSpecificOutput.additionalContext >/dev/null"
start worker-1 claude s-claude "\"$CL/s-claude.jsonl\"" compact >/dev/null
start verifier-1 codex cx1 null startup >/dev/null
start orchestrator claude s-gone "\"$WORK/none.jsonl\"" startup >/dev/null
printf '{"source":"startup"}' | HERDR_ROLE=worker-2 HERDR_PROJECT=demo "$SS" >/dev/null
check "세션 장부 머리글" "head -n 1 '$D/sessions.tsv' | grep -q '^epoch	time	role	tool	model	session_id	source	transcript'"
check "세션 시작·compact마다 장부에 한 줄" "[ \"\$(grep -c '	s-claude	' '$D/sessions.tsv')\" = 2 ] && grep -q '	worker-1	claude	m	s-claude	compact	' '$D/sessions.tsv'"
check "session_id가 없으면 장부에 남기지 않음" "! grep -q 'worker-2' '$D/sessions.tsv'"
check "역할의 현재 세션 기록" "[ \"\$(cat '$D/.worker-1.session')\" = s-claude ]"
export HERDR_ROLE=worker-1 HERDR_PROJECT=demo; oldpath="$PATH"; export PATH="$WORK/stub2:$PATH"
cd "$G"; "$R" "[완료] A-07 요약" >/dev/null 2>&1; cd "$ROOT"
export PATH="$oldpath"; unset HERDR_ROLE HERDR_PROJECT
check "보고마다 작업 경계 기록" "tail -n 1 '$D/reports.tsv' | awk -F'\t' '\$3==\"worker-1\" && \$4==\"s-claude\" && \$5==\"완료\" && \$6==\"A-07\"' | grep -q ."
check "작업 경계 머리글" "head -n 1 '$D/reports.tsv' | grep -q '^epoch	time	role	session_id	tag	task	sha'"
# 작업 대응 시험용으로 경계를 고정한다: worker-1이 2026-11-09T02:00Z에 A-01을 보고했다.
printf 'epoch\ttime\trole\tsession_id\ttag\ttask\tsha\n1794189600\tx\tworker-1\ts-claude\t완료\tA-01\t\n' >"$D/reports.tsv"
row() { TZ=UTC "$U" --project demo --tsv "$@" | awk -F'\t' -v k="$KEY" '$1==k'; }
KEY=worker-1; r="$(row --by role)"
check "Claude는 message.id로 중복 제거하고 서브에이전트를 포함" "[ \"\$(printf '%s' \"\$r\" | cut -f2-6)\" = \"\$(printf '3\t13\t1300\t7100\t170')\" ]"
check "단가표로 API 단가 환산" "[ \"\$(printf '%s' \"\$r\" | cut -f7)\" = 0.013408 ]"
KEY=verifier-1; r="$(row --by role)"
check "Codex는 response_id로 중복 제거하고 캐시 읽기를 입력에서 분리" "[ \"\$(printf '%s' \"\$r\" | cut -f2-6)\" = \"\$(printf '2\t300\t0\t1200\t40')\" ]"
check "단가 없는 모델은 비용을 비움" "[ -z \"\$(printf '%s' \"\$r\" | cut -f7)\" ]"
KEY=A-01; check "보고 시각까지의 사용량은 그 작업" "[ \"\$(row --by task | cut -f2)\" = 2 ]"
KEY='(보고 없음)'; check "보고 뒤 사용량은 보고 없음" "[ \"\$(row --by task | cut -f2)\" = 3 ]"
KEY=claude-sonnet-5-5; check "서브에이전트 모델을 따로 셈" "[ \"\$(row --by model | cut -f2)\" = 1 ]"
KEY=gpt-6.1-sol; check "Codex 모델은 turn_context에서" "[ \"\$(row --by model | cut -f2)\" = 2 ]"
KEY=worker-1; check "--since 이전 사용량 제외" "[ \"\$(row --by role --since 2026-11-09T02:30 | cut -f2)\" = 1 ]"
KEY=2026-11-09; check "일자별" "[ \"\$(row --by day | cut -f2)\" = 5 ]"
check "여러 기준으로 묶기" "TZ=UTC '$U' --project demo --tsv --by role,model | awk -F'\t' '\$1==\"worker-1\" && \$2==\"claude-opus-5-5\" && \$3==2' | grep -q ."
tbl="$(TZ=UTC "$U" --project demo)"
check "기록 없는 세션을 알림" "printf '%s' \"\$tbl\" | grep -q '기록 없음 1개: orchestrator'"
check "표에 합계" "printf '%s' \"\$tbl\" | grep -q '^합계'"
check "장부가 없으면 실패" "! '$U' --project nothing >/dev/null 2>&1"
check "알 수 없는 묶기 기준 거부" "! '$U' --project demo --by color >/dev/null 2>&1"
tsv="$(TZ=UTC "$U" --project demo --tsv)"
check "TSV 첫 줄에 비용 고지 주석" "printf '%s' \"\$tsv\" | head -n 1 | grep -q '^# .*API 단가로 환산.*구독.*단가 없는 모델: gpt-6.1-sol'"
check "TSV 머리글은 고지 다음 줄" "printf '%s' \"\$tsv\" | sed -n 2p | grep -q '^role	model	responses'"
check "실행기가 도구를 세션에 알림" "'$P/.agents/bin/herdr-session' --dry-run worker-1 claude | grep -q 'HERDR_TOOL=claude'"

echo "== 검사 결과 이어받기"
C="$P/.agents/bin/herdr-check"; D="$HOME/.claude/herdr/handoff/demo"
F="$WORK/flowrepo"; git init -q -b main "$F"; mkdir -p "$F/docs"
fcommit() { git -C "$F" add -A && git -C "$F" -c user.email=t@t -c user.name=t commit -q -m "$1"; }
echo count.log >"$F/.gitignore"; echo a >"$F/a.txt"; fcommit code
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD="echo run >>count.log"/; s/^HERDR_CHECK_SKIP_PATHS=.*/HERDR_CHECK_SKIP_PATHS="docs\/* *.md"/' "$P/.agents/harness.env"
export HERDR_ROLE=worker-7 HERDR_PROJECT=demo
rm -f "$D/.worker-7.check" "$D/checks.tsv"; cd "$F"
"$C" >/dev/null 2>&1; base="$(git rev-parse HEAD)"
check "검사 기록 머리글" "head -n 1 '$D/checks.tsv' | grep -q '^epoch	time	role	session_id	sha	result	seconds'"
check "검사마다 기록" "tail -n 1 '$D/checks.tsv' | awk -F'\t' '\$3==\"worker-7\" && \$5==\"$base\" && \$6==\"PASS\"' | grep -q ."
echo d >docs/x.md; echo r >README.md; fcommit docs
check "건너뛸 경로만 바뀌면 PASS를 이어받음" "[ \"\$('$C' --status)\" = \"PASS \$(git rev-parse HEAD) 이어받음 ${base:0:12}\" ]"
"$C" >/dev/null 2>&1
check "이어받으면 검사를 다시 돌리지 않음" "[ \"\$(wc -l <count.log | tr -d ' ')\" = 1 ]"
check "이어받음도 검사 기록에 남김" "grep -q '	INHERIT	' '$D/checks.tsv'"
echo b >b.txt; fcommit code2
check "코드가 바뀌면 이어받지 않음" "[ \"\$('$C' --status)\" = NONE ]"
"$C" >/dev/null 2>&1; base="$(git rev-parse HEAD)"
git mv -k b.txt docs/b.txt; fcommit move
check "코드를 건너뛸 경로로 옮겨도 이어받지 않음" "[ \"\$('$C' --status)\" = NONE ]"
"$C" >/dev/null 2>&1
echo w >docs/w.md; fcommit docs-w; echo z >docs/z.md
check "커밋 안 된 변경이 있으면 이어받지 않음" "[ \"\$('$C' --status)\" = NONE ]"
rm docs/z.md
set_env 's/^HERDR_CHECK_SKIP_PATHS=.*/HERDR_CHECK_SKIP_PATHS=/' "$P/.agents/harness.env"
echo y >docs/y.md; fcommit docs2
check "건너뛸 경로가 비면 이어받지 않음" "[ \"\$('$C' --status)\" = NONE ]"
check "검사 시간 제한 기본값은 넉넉하게" "grep -q '^HERDR_CHECK_TIMEOUT=3600' '$P/.agents/harness.env' && grep -q 'HERDR_CHECK_TIMEOUT=3600' '$C'"
if command -v timeout >/dev/null; then
  set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD="sleep 3"/; s/^HERDR_CHECK_TIMEOUT=.*/HERDR_CHECK_TIMEOUT=1/' "$P/.agents/harness.env"
  echo t >t.txt; fcommit slow; out="$("$C" 2>&1)"
  check "시간 초과면 지난 PASS 중 가장 긴 검사 시간을 알림" "printf '%s' \"\$out\" | grep -q '시간 초과' && printf '%s' \"\$out\" | grep -q '지난 PASS 중 가장 긴 검사'"
  set_env 's/^HERDR_CHECK_TIMEOUT=.*/HERDR_CHECK_TIMEOUT=3600/' "$P/.agents/harness.env"
fi
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD=/' "$P/.agents/harness.env"
cd "$ROOT"; unset HERDR_ROLE HERDR_PROJECT

echo "== 공용 검사 대기열"
export HERDR_HEAVY_DIR="$WORK/heavy" HERDR_HEAVY_POLL=0.1 HERDR_PROJECT=demo
Q="$P/.agents/bin/herdr-queue"; ORD="$WORK/order.log"; : >"$ORD"
wait_for() { local i; for i in $(seq 1 150); do grep -q "$1" "$2" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
check "빈 대기열" "[ \"\$('$Q' ahead)\" = 0 ] && '$Q' | grep -q '대기열이 비었다'"
"$Q" run --role a --sha aaa -- bash -c "echo a-start >>'$ORD'; sleep 1.5; echo a-end >>'$ORD'" &
wait_for a-start "$ORD"
"$Q" run --role b --sha bbb -- bash -c "echo b-start >>'$ORD'" 2>"$WORK/qb.err" &
sleep 0.5
check "대기열 표에 실행과 대기" "'$Q' | grep -E '^- +실행 +demo/a' >/dev/null && '$Q' | grep -E '^1 +대기 +demo/b' >/dev/null && [ \"\$('$Q' ahead)\" = 2 ]"
wait
check "무거운 검사는 하나씩" "[ \"\$(tr '\n' ' ' <'$ORD')\" = 'a-start a-end b-start ' ]"
check "기다리는 동안 순번과 앞 검사를 알림" "grep -q '1번째로 기다린다 · 앞: demo/a 실행' '$WORK/qb.err'"
: >"$ORD"
"$Q" run --role h -- bash -c "echo h >>'$ORD'; sleep 1.5" & wait_for '^h' "$ORD"
"$Q" run --role n1 -- bash -c "echo n1 >>'$ORD'" 2>/dev/null & sleep 0.3
"$Q" run --role n2 -- bash -c "echo n2 >>'$ORD'" 2>/dev/null & sleep 0.3
check "급함 표시" "'$Q' urgent n2 | grep -q '1건을 맨 앞으로'"
wait
check "급한 검사가 먼저 들어온 검사를 앞지름" "[ \"\$(tr '\n' ' ' <'$ORD')\" = 'h n2 n1 ' ]"
"$Q" urgent u1 >/dev/null
check "대기 중인 검사가 없으면 다음 검사에 급함 예약" "'$Q' | grep -q '다음 검사 급함 예약: demo/u1'"
: >"$ORD"
"$Q" run --role h -- bash -c "echo h >>'$ORD'; sleep 1.5" & wait_for '^h' "$ORD"
"$Q" run --role n1 -- bash -c "echo n1 >>'$ORD'" 2>/dev/null & sleep 0.3
"$Q" run --role u1 -- bash -c "echo u1 >>'$ORD'" 2>/dev/null & sleep 0.3
wait
check "예약한 역할의 다음 검사는 맨 앞에 섬" "[ \"\$(tr '\n' ' ' <'$ORD')\" = 'h u1 n1 ' ]"
check "예약은 한 번 쓰면 없어짐" "! '$Q' | grep -q '급함 예약'"
mkdir -p "$HERDR_HEAVY_DIR/tickets"
printf '{"id":"dead","project":"x","role":"r","sha":"","pid":999999,"prio":5,"created":1,"state":"run","started":1}' >"$HERDR_HEAVY_DIR/tickets/dead.json"
check "죽은 프로세스의 자리는 치움" "timeout 10 '$Q' run --role c -- true 2>/dev/null && [ ! -e '$HERDR_HEAVY_DIR/tickets/dead.json' ]"
rm -f "$HERDR_HEAVY_DIR/tickets/dead.json" # 위가 실패해도 뒤 검사가 멈추지 않게
"$Q" run --role h -- sleep 2 & sleep 0.3
check "시간 제한은 실행 시간에만(대기는 세지 않음)" "'$Q' run --role t --timeout 1 --wait-file '$WORK/qw' -- sleep 0.2 2>/dev/null && [ \"\$(cat '$WORK/qw')\" -ge 1 ]"
wait
"$Q" run --role k --timeout 1 -- bash -c "sleep 30 & echo \$! >'$WORK/qk.pid'; wait" 2>"$WORK/qk.err"; rc=$?
check "시간 초과면 124와 함께 프로세스 묶음째 끝냄" "[ $rc -eq 124 ] && sleep 0.5 && ! kill -0 \$(cat '$WORK/qk.pid') 2>/dev/null && grep -q '대기 시간은 세지 않았다' '$WORK/qk.err'"
HERDR_HEAVY_MAX_LOAD=0.0001 "$Q" run --role g -- true 2>"$WORK/qg.err" & gpid=$!
wait_for '시작을 미룬다' "$WORK/qg.err"
check "시작 가드를 넘지 못하면 자리를 쥐고 기다림" "grep -q '1분 부하' '$WORK/qg.err' && '$Q' | grep -qE '실행 +demo/g'"
kill "$gpid"; wait "$gpid" 2>/dev/null
check "중단되면 자리를 내놓음" "[ \"\$('$Q' ahead)\" = 0 ]"

echo "== 가벼운 검사와 무거운 검사"
export HERDR_ROLE=worker-8; cd "$F"; rm -f count.log "$D/.worker-8.check"
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD="echo light >>count.log"/; s/^HERDR_CHECK_HEAVY_CMD=.*/HERDR_CHECK_HEAVY_CMD="echo heavy >>count.log"/' "$P/.agents/harness.env"
echo h1 >h1.txt; fcommit heavy1; "$C" >/dev/null 2>&1
check "가벼운 단계 다음 무거운 단계" "[ \"\$(tr '\n' ' ' <count.log)\" = 'light heavy ' ]"
check "검사 기록에 대기열 시간" "tail -n 1 '$D/checks.tsv' | awk -F'\t' 'NF == 8 && \$6 == \"PASS\" && \$8 ~ /^[0-9]+\$/' | grep -q ."
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD="echo light >>count.log; false"/' "$P/.agents/harness.env"
rm -f count.log; echo h2 >h2.txt; fcommit heavy2
check "가벼운 단계가 실패하면 무거운 단계는 돌지 않음" "! '$C' >/dev/null 2>&1 && [ \"\$(tr '\n' ' ' <count.log)\" = 'light ' ]"
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD=/; s/^HERDR_CHECK_HEAVY_CMD=.*/HERDR_CHECK_HEAVY_CMD="sleep 0.3"/; s/^HERDR_CHECK_TIMEOUT=.*/HERDR_CHECK_TIMEOUT=2/' "$P/.agents/harness.env"
"$Q" run --role other -- sleep 3 & sleep 0.3
echo h3 >h3.txt; fcommit heavy3
check "무거운 단계만 있어도 검사, 대기열 대기는 시간 제한·실행 시간에 넣지 않음" "[ \"\$('$C' --status)\" = NONE ] && '$C' >/dev/null 2>&1 && tail -n 1 '$D/checks.tsv' | awk -F'\t' '\$6 == \"PASS\" && \$8 >= 2 && \$7 < 2' | grep -q ."
wait
set_env 's/^HERDR_CHECK_HEAVY_CMD=.*/HERDR_CHECK_HEAVY_CMD=/; s/^HERDR_CHECK_TIMEOUT=.*/HERDR_CHECK_TIMEOUT=3600/' "$P/.agents/harness.env"

echo "== 뒤에서 도는 검사와 쌓기"
export HERDR_ROLE=worker-9 HC_TERMINAL_ID=t77 XDG_CACHE_HOME="$WORK/cache"; oldpath="$PATH"; export PATH="$WORK/stub2:$PATH"
R="$P/.agents/bin/herdr-report"
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD="sleep 1; test ! -e fail.flag"/' "$P/.agents/harness.env"
git -C "$F" worktree add -q "$WORK/bgwt" -b stack; cd "$WORK/bgwt"
fcommit_wt() { git add -A && git -c user.email=t@t -c user.name=t commit -q -m "$1"; }
echo s0 >s0.txt; fcommit_wt s0; "$R" --bg "[완료] S-00 x" >/dev/null 2>&1; wait_for "S-00 x · 검사 PASS" "$WORK/hc.log"
echo s1 >s1.txt; fcommit_wt s1; s1="$(git rev-parse HEAD)"
# 검사용 worktree를 다시 쓸 때도 보고한 SHA를 검사하는지 보려고, 뒤 검사가 시작하기 전에 위 커밋을 쌓는다
(flock 9; sleep 1.5) 9>"$XDG_CACHE_HOME/herdr/check/demo/worker-9.lock" & sleep 0.2
: >"$WORK/hc.log"; out="$("$R" --bg "[완료] S-01 x" 2>&1)"
check "--bg는 곧바로 [진행]과 예상 시간을 보냄" "grep -q \"send t9 \\[진행\\] S-01 커밋 ${s1:0:12} 검사 중(뒤에서) 예상 최대 .*대기열\" '$WORK/hc.log' && printf '%s' \"\$out\" | grep -q '뒤에서 돌린다'"
touch fail.flag; fcommit_wt s2-stacked; s2="$(git rev-parse HEAD)"
wait_for "S-01 x · 검사 PASS" "$WORK/hc.log"
check "위에 쌓아도 뒤 검사는 보고한 SHA를 검사해 [완료]를 보냄" "grep -q \"send t9 \\[완료\\] S-01 x · 검사 PASS $s1\" '$WORK/hc.log'"
: >"$WORK/hc.log"; "$R" --bg "[완료] S-02 x" >/dev/null 2>&1
wait_for "S-02 커밋 ${s2:0:12} 검사 FAIL" "$WORK/hc.log"
check "뒤 검사가 실패하면 이 세션에 알리고 [완료]는 보내지 않음" "grep -q 'send t77 \\[검사 FAIL\\] S-02 커밋 ${s2:0:12}' '$WORK/hc.log' && grep -q 'send t9 \\[진행\\] S-02 커밋 ${s2:0:12} 검사 FAIL' '$WORK/hc.log' && ! grep -q '\\[완료\\] S-02' '$WORK/hc.log'"
check "실패 로그는 SHA별로 남김" "[ -e '$D/.worker-9.check-${s2:0:12}.log' ]"
check "--bg는 [완료]에만" "! '$R' --bg '[진행] S-03 x' >/dev/null 2>&1"
git rm -q fail.flag; fcommit_wt s3; "$P/.agents/bin/herdr-check" >/dev/null 2>&1; : >"$WORK/hc.log"
check "이미 통과한 SHA면 --bg도 바로 [완료]" "'$R' --bg '[완료] S-03 x' >/dev/null 2>&1 && grep -q '\\[완료\\] S-03 x · 검사 PASS' '$WORK/hc.log' && ! grep -q '\\[진행\\] S-03' '$WORK/hc.log'"
set_env 's/^HERDR_CHECK_CMD=.*/HERDR_CHECK_CMD=/' "$P/.agents/harness.env"
cd "$ROOT"; export PATH="$oldpath"; unset HERDR_ROLE HERDR_PROJECT HC_TERMINAL_ID XDG_CACHE_HOME HERDR_HEAVY_DIR HERDR_HEAVY_POLL

echo "== 받은 지시와 판정 기록"
TURN="$P/.agents/hooks/worker-turn.sh"; R="$P/.agents/bin/herdr-report"
rm -f "$D/received.tsv"
printf '{"prompt":"<hc from=\\"t1j\\">[배정] B-01 — 내용"}' | HERDR_ROLE=worker-7 HERDR_PROJECT=demo "$TURN" start
printf '{"prompt":"[병합] B-01, 판정 PASS"}' | HERDR_ROLE=worker-7 HERDR_PROJECT=demo "$TURN" start
printf '{"prompt":"그냥 질문"}' | HERDR_ROLE=worker-7 HERDR_PROJECT=demo "$TURN" start
check "받은 지시 기록 머리글" "head -n 1 '$D/received.tsv' | grep -q '^epoch	time	role	session_id	tag	task'"
check "배정을 받은 시각 기록" "awk -F'\t' '\$3==\"worker-7\" && \$5==\"배정\" && \$6==\"B-01\"' '$D/received.tsv' | grep -q ."
check "병합 지시도 기록(작업 ID 뒤 문장부호 제거)" "awk -F'\t' '\$5==\"병합\" && \$6==\"B-01\"' '$D/received.tsv' | grep -q ."
check "말머리 없는 입력은 기록하지 않음" "[ \"\$(wc -l <'$D/received.tsv' | tr -d ' ')\" = 3 ]"
PATH="$WORK/stub2:$PATH" HERDR_ROLE=verifier-1 HERDR_PROJECT=demo "$R" "[판정] B-01 ISSUES abc1234 /tmp/v.md" >/dev/null 2>&1
check "판정 결과와 SHA 기록" "tail -n 1 '$D/reports.tsv' | awk -F'\t' '\$5==\"판정\" && \$6==\"B-01\" && \$7==\"abc1234\" && \$8==\"ISSUES\"' | grep -q ."

echo "== 흐름 측정"
FL="$HOME/.claude/herdr/handoff/flow"; mkdir -p "$FL"; FLOW="$P/.agents/bin/herdr-flow"
printf 'epoch\ttime\trole\tsession_id\ttag\ttask\tsha\tresult\n' >"$FL/reports.tsv"
printf '%s\tx\t%s\ts\t%s\tB-01\t%s\t%s\n' 900 verifier-1 완료 '' '' 1000 worker-1 완료 sha1 '' 1300 verifier-1 판정 sha1 ISSUES 1500 worker-1 완료 sha2 '' 1700 verifier-1 판정 sha2 PASS 2600 worker-1 완료 sha3 '' 3000 worker-2 완료 sha9 '' >>"$FL/reports.tsv"
sed -i.bak 's/^3000\tx\tworker-2\ts\t완료\tB-01/3000\tx\tworker-2\ts\t완료\tC-01/' "$FL/reports.tsv" && rm -f "$FL/reports.tsv.bak"
printf 'epoch\ttime\trole\tsession_id\ttag\ttask\n400\tx\tworker-1\ts\t배정\tB-01\n2000\tx\tworker-1\ts\t병합\tB-01\n3100\tx\tworker-3\ts\t배정\tD-01\n3300\tx\tworker-3\ts\t병합\tD-01\n' >"$FL/received.tsv"
printf '3200\tx\tworker-3\ts\t완료\tD-01\t\t\n' >>"$FL/reports.tsv"
printf 'epoch\ttime\trole\tsession_id\tsha\tresult\tseconds\tqueue_s\n700\tx\tworker-1\ts\tsha1\tPASS\t300\t600\n1400\tx\tworker-1\ts\tsha2\tPASS\t100\n2400\tx\tworker-1\ts\tsha3\tINHERIT\t0\n2900\tx\tworker-2\ts\tsha9\tFAIL\t50\n' >"$FL/checks.tsv"
check "작업별: 작업·관문 대기·병합 시간, 검사, 판정" "'$FLOW' --project flow --tsv | grep -qxF \"\$(printf 'B-01\t600\t1000\t600\t3\t400\tISSUES>PASS')\""
check "병합 지시 뒤 완료가 없으면 병합 칸은 비움" "'$FLOW' --project flow --tsv | grep -qxF \"\$(printf 'D-01\t100\t100\t\t0\t0\t')\""
check "배정 기록이 없으면 그 칸은 비움" "'$FLOW' --project flow --tsv | grep -qxF \"\$(printf 'C-01\t\t\t\t1\t50\t')\""
ftbl="$("$FLOW" --project flow)"
check "표에 관문 대기 합계" "printf '%s' \"\$ftbl\" | grep -q '관문 대기 합계 18m20s'"
check "역할별 검사 요약(이어받음 포함)" "printf '%s' \"\$ftbl\" | grep -E '^worker-1 +3 +2 +0 +1 ' >/dev/null"
check "역할별 대기열 대기 시간(예전 기록은 0)" "printf '%s' \"\$ftbl\" | grep -E '^worker-1 .* 10m00s\$' >/dev/null && printf '%s' \"\$ftbl\" | grep -E '^worker-2 .* 0s\$' >/dev/null"
check "기록이 없으면 실패" "! '$FLOW' --project nothing >/dev/null 2>&1"

echo "== 검증자 정원"
mkdir -p "$WORK/vstub"
cat >"$WORK/vstub/hc" <<'EOF'
#!/usr/bin/env bash
# 전체 4개: orchestrator 1, 워커 2, 검증자(kind=verifier) 1.
case "$1" in run) echo '{"address":"t9"}'; exit 0 ;; esac
case "$*" in
  *role=orchestrator*) echo '{"terminals":[{"address":"t1"}]}' ;;
  *role=commander*) echo '{"terminals":[]}' ;;
  *kind=verifier*) echo '{"terminals":[{"address":"t4"}]}' ;;
  *) echo '{"terminals":[{"address":"t1"},{"address":"t2"},{"address":"t3"},{"address":"t4"}]}' ;;
esac
EOF
chmod +x "$WORK/vstub/hc"
S="$P/.agents/bin/herdr-session"
vs() { PATH="$WORK/vstub:$PATH" env -u HERDR_VIEW_ANCHOR "$S" "$@" codex >/dev/null 2>&1; }
check "세션에 kind 라벨" "'$S' --dry-run verifier-1 codex | grep -q -- '--label kind=verifier' && '$S' --dry-run worker-1 codex | grep -q -- '--label kind=worker'"
set_env 's/^HERDR_MAX_WORKERS=.*/HERDR_MAX_WORKERS=2/; s/^HERDR_MAX_VERIFIERS=.*/HERDR_MAX_VERIFIERS=1/' "$P/.agents/harness.env"
check "검증자는 워커 수에 넣지 않음(워커 2/2면 거부)" "! vs worker-3"
check "검증자 정원이 차면 거부" "! vs verifier-2"
set_env 's/^HERDR_MAX_VERIFIERS=.*/HERDR_MAX_VERIFIERS=2/' "$P/.agents/harness.env"
check "워커가 가득 차도 검증자는 정원 안이면 띄움" "vs verifier-2"
set_env 's/^HERDR_MAX_WORKERS=.*/HERDR_MAX_WORKERS=3/' "$P/.agents/harness.env"
check "워커는 워커 정원 안이면 띄움" "vs worker-3"

echo "== 실행기"
S="$P/.agents/bin/herdr-session"
c="$("$S" --dry-run --task '[배정] A-01' --model sonnet worker-1 claude high)"
for s in 'role=worker-1' 'project=demo' 'HERDR_ROLE=worker-1' 'HERDR_HOME=' 'bin:' 'HERDR_CTX_GUARD_OFF=1' 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000' 'dangerously-skip-permissions' 'model sonnet' 'effort high' 'A-01'; do
  check "claude 명령에 없음: $s" "printf '%s' \"\$c\" | grep -q -- '$s'"
done
c="$("$S" --dry-run orchestrator codex)"
for s in 'no-daemon' 'yolo' 'dangerously-bypass-hook-trust' 'model_auto_compact_token_limit=400000' 'gpt-6.1-terra'; do
  check "codex 명령에 없음: $s" "printf '%s' \"\$c\" | grep -q -- '$s'"
done
set_env 's/^HERDR_AUTONOMOUS=1/HERDR_AUTONOMOUS=0/' "$P/.agents/harness.env"
check "자율 모드 끄면 claude 권한 우회 없음" "! '$S' --dry-run worker-1 claude | grep -q dangerously"
check "자율 모드 끄면 codex yolo 없음" "! '$S' --dry-run worker-1 codex | grep -q yolo"
set_env 's/^HERDR_AUTONOMOUS=0/HERDR_AUTONOMOUS=1/' "$P/.agents/harness.env"
git -C "$P" add -A >/dev/null; git -C "$P" -c user.email=t@t -c user.name=t commit -qm init
git -C "$P" worktree add -q docs/.worktrees/w -b w
W="$P/docs/.worktrees/w/.agents/bin/herdr-session"
check "--here: hc 터미널 밖이면 hc 터미널을 열고 붙는다" "env -u HC_TERMINAL_ID '$S' --dry-run --here commander codex | grep -q '^hc run --bg --json --label role=commander --label project=demo.*&& hc attach'"
check "--here: hc 터미널 안이면 그 터미널에 라벨" "HC_TERMINAL_ID=t5 '$S' --dry-run --here commander codex | grep -q '^hc label t5 role=commander project=demo'"
check "워커는 부모(Orchestrator)가 끝나도 남음" "'$S' --dry-run worker-1 codex | grep -q -- '--outlive-parent'"
check "검증자도 부모가 끝나도 남음" "'$S' --dry-run verifier-1 claude | grep -q -- '--outlive-parent'"
check "--outlive-parent를 적어도 한 번만 붙음" "[ \"\$('$S' --dry-run --outlive-parent orchestrator codex | grep -o -- '--outlive-parent' | wc -l | tr -d ' ')\" = 1 ]"
check "도구 생략·설정 없음이면 거부" "! '$S' --dry-run worker-1 >/dev/null 2>&1"
check "harness.env 템플릿에 역할별 도구 칸" "grep -q '^HERDR_WORKER_TOOL=' '$P/.agents/harness.env' && grep -q '^HERDR_ORCHESTRATOR_TOOL=' '$P/.agents/harness.env'"
set_env 's/^HERDR_ORCHESTRATOR_TOOL=.*/HERDR_ORCHESTRATOR_TOOL=claude/; s/^HERDR_ORCHESTRATOR_MODEL=.*/HERDR_ORCHESTRATOR_MODEL=sonnet/; s/^HERDR_WORKER_TOOL=.*/HERDR_WORKER_TOOL=codex/; s/^HERDR_WORKER_MODEL=.*/HERDR_WORKER_MODEL=gpt-6.1-terra/; s/^HERDR_WORKER_EFFORT=.*/HERDR_WORKER_EFFORT=xhigh/' "$P/.agents/harness.env"
check "Orchestrator 도구·모델을 설정에서" "'$S' --dry-run orchestrator | grep -q 'claude .*--model sonnet --effort high'"
check "워커 도구·모델·effort를 설정에서" "'$S' --dry-run worker-1 | grep -q 'codex --no-daemon .*-m gpt-6.1-terra .*effort=\"xhigh\"'"
check "검증자도 워커 설정" "'$S' --dry-run verifier-1 | grep -q 'gpt-6.1-terra'"
check "effort 인자가 설정보다 우선" "'$S' --dry-run worker-1 low | grep -q 'effort=\"low\"'"
check "--model 인자가 설정보다 우선" "'$S' --dry-run --model gpt-x worker-1 | grep -q -- '-m gpt-x'"
check "다른 도구를 적으면 설정 모델을 넘기지 않음" "'$S' --dry-run verifier-1 claude | grep -q -- '--model opus --effort medium'"
check "검증자 설정 비면 워커 설정" "'$S' --dry-run verifier-1 | grep -q 'gpt-6.1-terra'"
set_env 's/^HERDR_VERIFIER_TOOL=.*/HERDR_VERIFIER_TOOL=claude/; s/^HERDR_VERIFIER_MODEL=.*/HERDR_VERIFIER_MODEL=opus/; s/^HERDR_VERIFIER_EFFORT=.*/HERDR_VERIFIER_EFFORT=xhigh/' "$P/.agents/harness.env"
check "검증자는 검증자 설정" "'$S' --dry-run verifier-1 | grep -q 'claude .*--model opus --effort xhigh'"
check "워커는 검증자 설정을 쓰지 않음" "'$S' --dry-run worker-1 | grep -q 'codex --no-daemon'"
set_env 's/^\(HERDR_[A-Z]*_TOOL\)=.*/\1=/; s/^\(HERDR_[A-Z]*_MODEL\)=.*/\1=/; s/^\(HERDR_[A-Z]*_EFFORT\)=.*/\1=/' "$P/.agents/harness.env"
check "역할 설정을 다시 비움" "! grep -qE '^HERDR_[A-Z]+_(TOOL|MODEL|EFFORT)=.' '$P/.agents/harness.env'"
check "worktree에서도 프로젝트 이름 유지" "'$W' --dry-run worker-1 claude | grep -q 'project=demo'"
mkdir -p "$WORK/stub"
cat >"$WORK/stub/hc" <<'EOF'
#!/usr/bin/env bash
# 실제 hc ls처럼 출력에 라벨을 넣지 않고 --label 필터로만 거른다. 전체 3개: orchestrator 1, 워커 2.
case "$*" in
  *role=orchestrator*) echo '{"terminals":[{"address":"t1"}]}' ;;
  *role=commander*) echo '{"terminals":[]}' ;;
  *) echo '{"terminals":[{"address":"t1"},{"address":"t2"},{"address":"t3"}]}' ;;
esac
EOF
chmod +x "$WORK/stub/hc"
set_env 's/^HERDR_MAX_WORKERS=.*/HERDR_MAX_WORKERS=2/' "$P/.agents/harness.env"
check "워커 상한 초과 거부" "! PATH='$WORK/stub:$PATH' '$S' worker-3 claude >/dev/null 2>&1"
set_env 's/^HERDR_MAX_WORKERS=.*/HERDR_MAX_WORKERS=3/' "$P/.agents/harness.env"
check "Orchestrator는 워커 수에 넣지 않음" "PATH='$WORK/stub:$PATH' '$S' worker-3 claude >/dev/null 2>&1; [ \$? -ne 1 ] || ! PATH='$WORK/stub:$PATH' '$S' worker-3 claude 2>&1 | grep -q '이미'"

echo "== 보기 패널"
check "--here는 사용자 패널을 기준으로 넘김" "env -u HC_TERMINAL_ID HERDR_PANE_ID=w9:p1 '$S' --dry-run --here commander codex | grep -q 'HERDR_VIEW_ANCHOR=w9:p1'"
check "자식 세션에 기준 패널 전달" "HERDR_VIEW_ANCHOR=w9:p1 HERDR_PANE_ID=w0:p0 '$S' --dry-run worker-1 codex | grep -q 'HERDR_VIEW_ANCHOR=w9:p1'"
check "hc 터미널 안의 --here는 기준을 만들지 않음" "! env -u HERDR_VIEW_ANCHOR HC_TERMINAL_ID=t5 HERDR_PANE_ID=w0:p0 '$S' --dry-run --here commander codex | grep -q HERDR_VIEW_ANCHOR"
check "띄울 때 부모 Claude 세션 표지와 낡은 패널 ID를 지움" "CLAUDE_CODE_CHILD_SESSION=1 '$S' --dry-run worker-1 claude | grep -q -- '-u CLAUDE_CODE_CHILD_SESSION .*-u HERDR_PANE_ID'"
check "지운 뒤에도 자기 compact 값은 넘김" "'$S' --dry-run worker-1 claude | grep -q 'CLAUDE_CODE_AUTO_COMPACT_WINDOW='"
V="$P/.agents/bin/herdr-view"
mkdir -p "$WORK/hstub"
cat >"$WORK/hstub/herdr" <<'EOF'
#!/usr/bin/env bash
# 가짜 herdr: 탭 w1:t1에 기준 w1:p1, VIEWS에 적힌 보기 패널(id/label/height)을 둔다.
echo "$*" >>"$HLOG"
panes='{"pane_id":"w1:p1","tab_id":"w1:t1"},{"pane_id":"w2:p1","tab_id":"w2:t1","label":"hc:worker-9"}'
rects='{"pane_id":"w1:p1","rect":{"height":38}}'
for v in $VIEWS; do IFS=/ read -r id lb h <<<"$v"
  panes+=",{\"pane_id\":\"$id\",\"tab_id\":\"w1:t1\",\"label\":\"$lb\"}"; rects+=",{\"pane_id\":\"$id\",\"rect\":{\"height\":$h}}"; done
case "$1 $2" in
  "pane list") echo "{\"result\":{\"panes\":[$panes]}}" ;;
  "pane layout") echo "{\"result\":{\"layout\":{\"panes\":[$rects]}}}" ;;
  "pane split") echo '{"result":{"pane":{"pane_id":"w1:p9"}}}' ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "$WORK/hstub/herdr"
export HLOG="$WORK/herdr.log"
: >"$HLOG"; PATH="$WORK/hstub:$PATH" VIEWS="" "$V" w1:p1 t7 orchestrator 2>/dev/null
check "첫 보기 패널은 기준 오른쪽" "grep -q '^pane split w1:p1 --direction right --no-focus' '$HLOG'"
check "보기 패널 이름과 크기를 맞추는 접속" "grep -q '^pane rename w1:p9 hc:orchestrator' '$HLOG' && grep -q '^pane run w1:p9 hc attach t7; exit' '$HLOG'"
: >"$HLOG"; PATH="$WORK/hstub:$PATH" VIEWS="w1:p2/hc:orchestrator/10 w1:p3/hc:worker-1/19" "$V" w1:p1 t8 worker-2 2>/dev/null
check "다음 보기 패널은 가장 높은 보기 패널 아래" "grep -q '^pane split w1:p3 --direction down' '$HLOG'"
check "다른 탭의 보기 패널은 세지 않음" "! grep -q 'w2:p1' '$HLOG'"
: >"$HLOG"; PATH="$WORK/hstub:$PATH" VIEWS="w1:p2/hc:worker-1/19" "$V" w1:p1 t9 worker-1 2>/dev/null
check "같은 역할의 보기 패널이 있으면 만들지 않음" "! grep -q '^pane split' '$HLOG'"
: >"$HLOG"; PATH="$WORK/hstub:$PATH" VIEWS="" "$V" w5:p5 t9 worker-1 2>/dev/null; rc=$?
check "기준 패널이 없으면 실패하고 나누지 않음" "[ $rc -ne 0 ] && ! grep -q '^pane split' '$HLOG'"
mkdir -p "$WORK/hcstub"
printf '#!/usr/bin/env bash\ncase "$1" in run) echo "{\\"address\\":\\"t42\\"}" ;; *) echo "{\\"terminals\\":[]}" ;; esac\n' >"$WORK/hcstub/hc"
chmod +x "$WORK/hcstub/hc"
out="$(PATH="$WORK/hcstub:$WORK/hstub:$PATH" HLOG=/dev/null VIEWS="" HERDR_VIEW_ANCHOR=w5:p5 "$S" worker-1 codex 2>/dev/null)"; rc=$?
check "보기 패널 실패가 세션 띄우기를 막지 않음" "[ $rc -eq 0 ] && [ '$out' = t42 ]"
: >"$HLOG"; PATH="$WORK/hcstub:$WORK/hstub:$PATH" VIEWS="" HERDR_VIEW_ANCHOR=w1:p1 "$S" worker-1 codex >/dev/null 2>&1
check "세션을 띄우면 보기 패널을 만든다" "grep -q '^pane run w1:p9 hc attach t42; exit' '$HLOG'"
set_env 's/^HERDR_VIEW_PANES=.*/HERDR_VIEW_PANES=0/' "$P/.agents/harness.env"
: >"$HLOG"; PATH="$WORK/hcstub:$WORK/hstub:$PATH" VIEWS="" HERDR_VIEW_ANCHOR=w1:p1 "$S" worker-1 codex >/dev/null 2>&1
check "HERDR_VIEW_PANES=0이면 만들지 않음" "! grep -q '^pane split' '$HLOG'"
set_env 's/^HERDR_VIEW_PANES=.*/HERDR_VIEW_PANES=1/' "$P/.agents/harness.env"
unset HLOG

echo "== 문서"
W_REF="$P/.agents/skills/running-herdr-autopilot/references/worker.md"; O_REF2="$P/.agents/skills/running-herdr-autopilot/references/orchestrator.md"
check "워커: 뒤 검사와 쌓기, 보고한 SHA까지만 병합" "grep -q 'herdr-report --bg' '$W_REF' && grep -q '쌓은 작업이 있을 때 병합' '$W_REF' && grep -q '검사 중인 커밋은 amend' '$W_REF'"
check "워커: 무거운 명령은 대기열 아래서" "grep -q 'herdr-queue run --role' '$W_REF'"
check "Orchestrator: 대기열 순번으로 만료, 급함은 임계 경로만" "grep -q 'herdr-queue urgent' '$O_REF2' && grep -q '임계 경로에만 쓴다' '$O_REF2'"
check "저장소 전체 링크" "python3 -I '$ROOT/core/skills/writing-project-docs/scripts/check_md_links.py' '$ROOT/README.md' '$ROOT/core' '$ROOT/docs' '$ROOT/templates' >/dev/null"
check "설치된 docs 색인" "python3 -I '$ROOT/core/skills/writing-project-docs/scripts/check_md_links.py' '$P/docs' >/dev/null"

echo "결과: 통과 $pass, 실패 $fail"
[ "$fail" -eq 0 ]
