#!/usr/bin/env bash
# 셸 명령 직전(PreToolUse) 되풀이된 함정을 막는다. 막으면 끝 코드 2와 stderr로 고치는 방법을 돌려준다.
# 규칙 문구로는 막지 못한 것만 담는다(jobtailor 워커 세션 측정, docs/dreaming/measurement.md).
#   zsh에서 따옴표 없는 '='로 시작하는 낱말(echo ====, [ a == b ]): zsh가 명령 경로로 바꾸려다 "not found"로 실패
#   timeout으로 감싼 herdr-report: 관문 검사 도중 죽어 보고가 가지 않는다
#   백그라운드 herdr-report(도구의 run_in_background, 끝의 &): 보고 시각이 다음 턴으로 밀려 Stop hook이 미보고로 본다
#   커밋 검사 건너뛰기(core.hooksPath=/dev/null, --no-verify)
#   git merge·rebase 출력을 파이프로 넘긴 뒤 &&로 잇기: 파이프가 실패를 가려 다음 단계가 이어진다
# 따옴표 안 글자와 히어독 본문은 보지 않는다. 명령을 읽지 못하면 막지 않는다.
command -v jq >/dev/null || exit 0
input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null)"
# Codex는 셸 도구 이름을 확인하지 못해 matcher 없이 등록한다. patch 본문은 명령이 아니다.
case "$tool" in apply_patch | Edit | Write | MultiEdit | NotebookEdit) exit 0 ;; esac
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // "" | if type == "array" then join(" ") else . end' 2>/dev/null)"
[[ -n "$cmd" ]] || exit 0
bg="$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)"

# shortcut: 히어독이 있으면 그 줄 뒤는 보지 않는다. 히어독 뒤의 명령까지 봐야 하면 종료 표지를 찾아 건너뛴다.
plain="$(printf '%s\n' "$cmd" | awk '{print} /<</{exit}' |
  sed -E -e "s/'[^']*'|\"([^\"\\\\]|\\\\.)*\"//g" -e 's/\$?\(\([^)]*\)\)//g' -e 's/\[\[[^]]*\]\]//g')"

deny() { printf '%s\n' "bash-guard: $1" >&2; exit 2; }

if [[ "${SHELL##*/}" == zsh ]] && printf '%s\n' "$plain" | grep -Eq '(^|[[:space:];|&(])=[^[:space:]]'; then
  deny "zsh는 따옴표 없이 '='로 시작하는 낱말(예: echo ====, [ \"\$a\" == b ])을 명령 경로로 바꾸려다 실패한다. 구분선은 따옴표로 감싸고(echo '===='), 비교는 [ \"\$a\" = b ] 또는 [[ \$a == b ]]를 쓴다."
fi
if printf '%s\n' "$plain" | grep -Eq '(^|[^[:alnum:]_-])timeout[[:space:]][^;|&]*herdr-report'; then
  deny "herdr-report를 timeout으로 감싸지 않는다. 관문 검사 도중 죽으면 보고가 가지 않는다. 검사가 오래 걸리면 herdr-report --bg \"[완료] …\"를 쓴다(곧바로 돌아온다)."
fi
if printf '%s\n' "$plain" | grep -Eq 'herdr-report' &&
  { [[ "$bg" == true ]] || printf '%s\n' "$plain" | grep -Eq 'herdr-report[^;|&]*[^>&]&([^&>]|$)'; }; then
  deny "herdr-report를 백그라운드로 돌리지 않는다. 보고 시각이 다음 턴으로 밀려 Stop hook이 보고 없는 턴으로 본다. 앞에서 실행하고, 검사가 오래 걸리면 herdr-report --bg \"[완료] …\"를 쓴다."
fi
if printf '%s\n' "$plain" | grep -Eq 'core\.hooksPath=/dev/null|git[[:space:]][^;|&]*(commit|push)[^;|&]*[[:space:]]--no-verify'; then
  deny "커밋 검사(pre-commit 등)를 건너뛰지 않는다. 중간(WIP) 커밋이라도 검사를 통과시킨다. 실패 테스트만 따로 커밋하지 말고 고친 코드와 함께 커밋한다. 검사가 틀렸다고 보면 [차단]으로 올린다."
fi
if printf '%s\n' "$plain" | grep -Eq 'git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?(merge|rebase)([[:space:]]([^;&|]|[0-9]?>&[0-9])*)?\|[^|;&][^;&|]*&&'; then
  deny "git merge·rebase 출력을 파이프(| tail 등)로 넘긴 뒤 &&로 잇지 않는다. 파이프의 끝 코드는 tail의 것이라 병합이 실패해도 다음 단계가 돈다. 병합을 따로 실행하고 끝 코드를 본 뒤 잇는다."
fi
exit 0
