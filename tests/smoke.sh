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
for f in AGENTS.md CLAUDE.md intent.md .gitignore .agents/harness.env .claude/settings.json .codex/hooks.json docs/status/work-plan.md docs/status/decisions.tsv .agents/bin/herdr-session .agents/bin/herdr-view .agents/bin/herdr-check .agents/hooks/check-edit.sh .agents/hooks/context-signal.sh .agents/skills/running-herdr-autopilot/SKILL.md .agents/skills/writing-project-docs/scripts/check_md_links.py; do
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
check "첫 묶음 선통과" "grep -q '첫 의존 묶음 하나만 배정' '$O_REF'"
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
check "저장소 전체 링크" "python3 -I '$ROOT/core/skills/writing-project-docs/scripts/check_md_links.py' '$ROOT/README.md' '$ROOT/core' '$ROOT/docs' '$ROOT/templates' >/dev/null"
check "설치된 docs 색인" "python3 -I '$ROOT/core/skills/writing-project-docs/scripts/check_md_links.py' '$P/docs' >/dev/null"

echo "결과: 통과 $pass, 실패 $fail"
[ "$fail" -eq 0 ]
