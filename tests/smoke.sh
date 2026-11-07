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

P="$WORK/demo"
"$ROOT/bin/harness" init "$P" >/dev/null

echo "== 설치"
for f in AGENTS.md CLAUDE.md intent.md .gitignore .agents/harness.env .claude/settings.json .codex/hooks.json docs/status/work-plan.md docs/status/decisions.tsv .agents/bin/herdr-session .agents/hooks/context-signal.sh .agents/skills/running-herdr-autopilot/SKILL.md .agents/skills/writing-project-docs/scripts/check_md_links.py; do
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
"$R" "[완료] A-01 요약" >/dev/null
check "보고가 Orchestrator로 감" "grep -q 'send t9 \\[완료\\] A-01' '$WORK/hc.log'"
rm -f "$D/.worker-1.compacts"; echo 123456 >"$D/.worker-1.ctx"; "$R" "[진행] x" >/dev/null
check "보고에 맥락 크기 자동 첨부" "grep -q 'ctx 123k · compact 0' '$WORK/hc.log'"
check "보고하면 막지 않음" "[ -z \"\$(echo '{}' | '$TURN' stop)\" ]"
check "Orchestrator·Commander는 막지 않음" "[ -z \"\$(echo '{}' | HERDR_ROLE=orchestrator '$TURN' stop)\" ]"
: >"$WORK/hc.log"
check "보고 대상 없으면 실패" "! HERDR_ROLE=orchestrator '$R' '[완료] x' >/dev/null 2>&1"
export PATH="$oldpath"; unset HERDR_ROLE HERDR_PROJECT

echo "== 실행기"
S="$P/.agents/bin/herdr-session"
c="$("$S" --dry-run --task '[배정] A-01' --model sonnet worker-1 claude high)"
for s in 'role=worker-1' 'project=demo' 'HERDR_ROLE=worker-1' 'HERDR_HOME=' 'bin:' 'HERDR_CTX_GUARD_OFF=1' 'CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000' 'dangerously-skip-permissions' 'model sonnet' 'effort high' 'A-01'; do
  check "claude 명령에 없음: $s" "printf '%s' \"\$c\" | grep -q -- '$s'"
done
c="$("$S" --dry-run orchestrator codex)"
for s in 'yolo' 'dangerously-bypass-hook-trust' 'model_auto_compact_token_limit=400000' 'gpt-6.1-terra'; do
  check "codex 명령에 없음: $s" "printf '%s' \"\$c\" | grep -q -- '$s'"
done
sed -i '' 's/^HERDR_AUTONOMOUS=1/HERDR_AUTONOMOUS=0/' "$P/.agents/harness.env"
check "자율 모드 끄면 claude 권한 우회 없음" "! '$S' --dry-run worker-1 claude | grep -q dangerously"
check "자율 모드 끄면 codex yolo 없음" "! '$S' --dry-run worker-1 codex | grep -q yolo"
sed -i '' 's/^HERDR_AUTONOMOUS=0/HERDR_AUTONOMOUS=1/' "$P/.agents/harness.env"
git -C "$P" add -A >/dev/null; git -C "$P" -c user.email=t@t -c user.name=t commit -qm init
git -C "$P" worktree add -q docs/.worktrees/w -b w
W="$P/docs/.worktrees/w/.agents/bin/herdr-session"
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
sed -i '' 's/^HERDR_MAX_WORKERS=.*/HERDR_MAX_WORKERS=2/' "$P/.agents/harness.env"
check "워커 상한 초과 거부" "! PATH='$WORK/stub:$PATH' '$S' worker-3 claude >/dev/null 2>&1"
sed -i '' 's/^HERDR_MAX_WORKERS=.*/HERDR_MAX_WORKERS=3/' "$P/.agents/harness.env"
check "Orchestrator는 워커 수에 넣지 않음" "PATH='$WORK/stub:$PATH' '$S' worker-3 claude >/dev/null 2>&1; [ \$? -ne 1 ] || ! PATH='$WORK/stub:$PATH' '$S' worker-3 claude 2>&1 | grep -q '이미'"

echo "== 문서"
check "저장소 전체 링크" "python3 -I '$ROOT/core/skills/writing-project-docs/scripts/check_md_links.py' '$ROOT/README.md' '$ROOT/core' '$ROOT/docs' '$ROOT/resources' '$ROOT/templates' >/dev/null"
check "설치된 docs 색인" "python3 -I '$ROOT/core/skills/writing-project-docs/scripts/check_md_links.py' '$P/docs' >/dev/null"

echo "결과: 통과 $pass, 실패 $fail"
[ "$fail" -eq 0 ]
