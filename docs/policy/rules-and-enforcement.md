# 규칙과 강제 수단

규칙마다 무엇이 지키게 하는지와, 그 규칙이 어떤 전제 위에 있는지 적는다. 모델이나 도구를 바꿀 때 전제를 다시 시험하고, 필요 없어진 규칙은 지운다.

강제 수단이 "문구"인 규칙은 어겨도 아무것도 실패하지 않는다. 같은 위반이 두 번 나오면 구조, 타입, 린트, 테스트 순서로 올린다. 시험은 한 번에 하나만 빼서 결과를 비교한다.

| 규칙 | 강제 수단 | 전제 | 제거 시험 |
| --- | --- | --- | --- |
| 모든 워커 턴은 보고로 끝난다 | `Stop` hook(`worker-turn.sh`), `[미보고]` | 화면에만 쓰고 보고를 빠뜨려 진행이 멈춘다(실측) | hook을 끄고 미보고 빈도를 잰다 |
| 세션은 시작·정리 뒤 역할을 받는다 | `SessionStart` hook(`session-start.sh`) | 지침 안내만으로는 전역 스킬을 읽는다(실측) | 전역 스킬을 정리한 뒤 주입을 줄여 본다 |
| compact 뒤 상태를 복구한다 | `PreCompact`·`SessionStart` hook | compact 요약이 수용 기준과 결정을 잃을 수 있다 | 복구 주입을 끄고 재작업을 비교한다 |
| 워커 수 상한 | 실행기(`herdr-session`, `kind` 라벨). `--here`로 연 패널은 세지 않는다 | 세션이 많으면 비용과 충돌이 늘어난다 | 상한을 바꿔 완료 시간과 비용을 잰다(`herdr-flow`, `herdr-usage`) |
| harness.env에 적힌 역할별 모델·effort는 띄우는 세션이 바꾸지 않는다 | 실행기(`herdr-session`)가 다른 `--model`·effort 인자를 거부한다 | 표 문구만 두면 Orchestrator가 작업 난도를 들어 사용자 설정보다 높은 모델을 고른다(ohmystock: 설정 sonnet/medium인데 워커를 opus high·xhigh로 띄움) | 거부를 경고로 바꾸고 설정과 다른 세션이 생기는지 본다 |
| 세션은 Commander, Orchestrator, 워커로 나눈다 | 라벨과 실행기, 역할 문구 | 분리가 사용자 맥락과 구현 맥락을 지킨다 | Commander 없이 Orchestrator와 직접 대화한다 |
| 의존 묶음은 같은 세션, 연관 작업은 맥락 있는 세션에 준다 | 문구, 세션 장부 | 재사용이 새 세션보다 재탐색과 충돌을 줄인다 | 같은 작업을 새 세션 기본으로 돌려 비교한다 |
| 작업 경계에서 정리하고 작업 중에는 compact에 맡긴다 | 문구, 소프트 신호 | 무관한 맥락은 품질을 떨어뜨리고 매 턴 비용이 된다 | 400k 값을 올려 비용과 재작업을 비교한다 |
| 워커는 소프트 신호에도 계속한다 | hook 문구 | 한도 근처에서 마무리를 재촉하면 미완성 보고가 나온다 | 300k에 이른 실제 세션에서 미완성 보고를 센다 |
| 워커는 연관 없는 다른 작업을 `/clear` 뒤에 시작하고, 연관 작업은 맥락 크기와 무관하게 이어 간다. Orchestrator·Commander의 자기 정리는 스킬에 따로 정한 예외다 | 문구, 세션 장부의 맥락 칸 | 연관 맥락은 재탐색을 줄이고, 크기는 compact가 관리할 수 있다(미측정) | compact를 여러 번 겪은 세션의 재작업과 비용을 정리 후 배정과 비교한다 |
| 연관 높은 세션이 바쁘면 장부에 예약하고 기다린다 | 문구, 세션 장부의 다음 예약 칸 | 기다리는 비용이 다른 세션의 재탐색보다 작다(미측정) | 같은 작업을 빈 세션 즉시 배정과 비교해 대기, 재탐색, 전체 완료 시간을 잰다 |
| 완료는 근거로 판정하고 추론·미확인은 통과가 아니다 | 문구, Orchestrator 대조 | 자기 보고는 부분 확인을 전체 확인처럼 말할 수 있다 | 사람이 찾은 결함과 보고를 대조한다 |
| 주석, 문서, 보고는 단서다 | 문구 | 틀린 주석과 보고가 판단을 흐린다 | 틀린 주석을 심은 작업으로 비교한다 |
| 코드는 실패 테스트부터 쓰고, 분기 변경은 뮤테이션으로 확인한다 | 문구(`implementing-with-tdd`), 프로젝트 검사·뮤테이션 명령 | 구현을 보고 쓴 테스트는 결함을 그대로 기대값으로 굳힌다 | 같은 작업을 TDD 없이 돌려 리뷰 단계 결함 수를 비교한다 |
| 주석 제한, 타입 원칙 | 문구, 프로젝트 검사 명령 | 기계 검사가 설명보다 오래 맞는다 | `decisions.tsv`의 사례가 없으면 줄인다 |
| 첫 코드 묶음의 첫 `[완료]`를 받아들인 뒤 나머지 코드 묶음을 배정한다. 조사·스펙·문서는 처음부터 병행한다 | 문구 | 배정 결함이 병렬로 번지면 비용이 크다. 결함은 첫 `[완료]` 대조에서 드러나고, 병합까지 기다리는 몫은 대기만 늘린다(zip-viewer 2026-11-09 대기 사례) | 첫 묶음에서 고친 결함이 없으면 작은 계획에서 뺀다 |
| 바뀐 파일이 모두 건너뛸 경로면 앞 검사 PASS를 이어받는다 | `herdr-check`(`HERDR_CHECK_SKIP_PATHS`, 이름 변경을 풀어 옮기기 전 경로도 봄) | 그 경로의 파일은 검사 결과를 바꾸지 않는다. 프로젝트가 경로를 고를 때 확인한다 | 이어받은 SHA에서 검사를 다시 돌려 결과가 갈린 적이 있는지 본다 |
| 독립 검증 | `[배정]`의 `독립 검증:`을 hook이 기록, `herdr-report`가 그 패치의 판정 PASS 없이는 `[완료]`를 보내지 않음 | 쓴 세션의 자기 판정은 결함을 놓친다 | 아래 "독립 검증 시험" |
| 독립 검증은 검증 세션이 아니라 작업한 워커가 띄운 서브에이전트가 한다. 설정한 도구·모델로, 그 SHA의 검증 전용 worktree에서 `[배정]` 원문만 받는다 | `herdr-verify`(`HERDR_VERIFIER_*`, `codex exec`·`claude -p`, hook이 저장한 `[배정]` 원문, 작성자 worktree 경로 지움), 실행기가 `verifier-*` 거부 | 검증 세션을 따로 두면 검증 대기열(`HERDR_MAX_VERIFIERS`), Orchestrator를 거친 판정 중계·보완 배정·재검증 왕복이 관문 대기를 늘렸다(zip-viewer U-R4: 검증 4회·보완 3회, 병합 지시까지 1h31m). 작성자의 설명은 검증자를 묶는다(시험 2: 작성자 worktree에서 실행) | `herdr-flow`의 관문 대기와 검증 시간을 검증 세션 시기와 비교한다. 판정 ISSUES 중 오탐 비율을 본다 |
| 검사와 독립 검증은 함께 뒤에서 돈다. `[완료]`는 같은 패치의 둘 다 PASS 뒤 | `herdr-report`(검사와 `herdr-verify`를 함께 돌리고 검사 FAIL이면 검증 취소), 판정은 `git patch-id`에 묶음 | 둘은 서로의 결과를 입력으로 쓰지 않는다. 검사 대기열 뒤에서 검증이 놀았다(zip-viewer에서 규칙 밖 병행 4건). rebase로 SHA만 바뀐 패치를 다시 검증할 이유가 없다 | 검사 PASS 뒤에만 검증하는 방식과 `[완료]`까지 시간·검증 토큰을 비교한다 |
| ISSUES는 작성 워커가 직접 받아 고치고, 같은 작업의 검증은 `[배정]`마다 정한 횟수까지다 | `herdr-report`가 그 워커에 `[판정]`을 보냄, `herdr-verify`가 `HERDR_VERIFY_MAX_ROUNDS`를 넘으면 거부, 재검증은 앞 기록을 받아 지적 항목만 봄 | 같은 지적을 두고 고치고 다시 받기가 끝없이 돌았다(zip-viewer U-R4) | 횟수 초과로 `[차단]`된 작업이 실제로 막힌 것이었는지 본다 |
| 무거운 검사는 기계 전체가 함께 쓰는 대기열에서 돌고, 시간 제한은 실행에만 건다 | `herdr-check`(`HERDR_CHECK_HEAVY_CMD`)·`herdr-queue`(자리, 급함, 메모리·부하 가드, 프로세스 묶음 정리) | 겹친 테스트가 다른 세션을 OOM으로 죽였고, 대기를 시간 제한에 넣어 급한 검사가 대기열 뒤에서 실패했다. 린트는 무거운 검사를 12분 기다렸다(zip-viewer 2026-11-09) | `herdr-flow`의 역할별 대기열 시간과 OOM·시간 초과 횟수를 본다 |
| 검사를 뒤에서 돌리는 동안 같은 묶음의 다음 작업을 쌓는다. 병합은 보고한 SHA까지만 | `herdr-report --bg`(보고한 SHA를 별도 worktree에서 검사, PASS면 자동 `[완료]`, FAIL이면 작성 세션에 알림), 문구 | 검사 대기 중 워커가 놀았다. 검사·판정은 SHA에 묶이므로 위에 쌓아도 관문은 그대로다 | 쌓은 작업 중 아래 커밋 실패로 옮긴 비율과, `[완료]`부터 다음 `[완료]`까지 시간을 본다 |
| 대기에는 소요 시간을 예측해 만료를 두고, 만료되면 진행부터 확인한다 | 문구, 상태판 대기 표, `herdr-flow`의 지난 기록 | 만료 없는 대기는 원인을 확인하지 않은 채 무한정 이어진다(실측). 테스트는 수 시간 걸릴 수 있어 짧은 고정 만료는 정상 작업을 끊는다 | 만료 처리 기록 중 대기를 실제로 줄인 비율과, 진행 중이었는데 끊은 비율을 본다 |
| 작업 상태는 보고 말머리로만 판단한다. 병합은 `[병합완료]`, 질문 답은 `[답변]` | `herdr-report`(`[병합완료]`는 SHA가 기본 브랜치에 들어 있고 검사 PASS 기록이 있어야 보낸다), 턴 종료 hook 문구, Orchestrator 문구 | 보고 종류가 검사 관문에 묶여 있으면 워커가 검사를 피하려고 `[차단]`이나 `hc send` 직접 발송으로 대신해 Orchestrator가 완료를 잘못 판단한다(zip-viewer 하네스 분석 P3, 2026-11-09) | `reports.tsv` 밖의 직접 발송과 말머리를 잘못 쓴 보고가 줄었는지 Orchestrator transcript로 센다 |
| 메인 체크아웃에서는 검사하지 않는다 | `herdr-report`(커밋된 HEAD만 보고, PASS 기록이 없으면 검사용 worktree에서 검사), `herdr-check --status-of` | 메인 체크아웃에는 다른 세션의 변경이 늘 있어 기록 키가 `+dirty`로 어긋나고, 잠금 없는 전체 검사가 돌아 메모리가 2 GiB까지 떨어졌다(zip-viewer P2) | 메인 체크아웃에서 돈 전체 검사 수를 `checks.tsv`로 센다 |
| 뒤에서 도는 검사의 자동 보고는 세션의 턴 보고로 세지 않는다 | `herdr-report --bg-run`이 보고 시각 기록을 남기지 않는다 | 자동 보고가 쌓은 작업을 하던 턴을 보고한 것으로 만들어 그 턴이 조용히 끝날 수 있다(코드 확인) | 빼면 smoke의 해당 검사가 실패한다 |
| 판정은 rebase 뒤 `git patch-id`가 같을 때만 유지한다. 병합은 빨리 감기로만 한다 | 문구(명령 포함), `[병합완료]`의 PASS 기록 확인(병합 커밋은 기록이 없어 다시 검사된다) | "충돌이나 코드 수정이 없었다"는 작성자 판단은 바로 옆 줄 변경을 놓친다. 병합 커밋은 검사하지 않은 트리다 | 판정 유지 뒤 기본 브랜치에서 찾은 결함 수를 본다 |
| 완료는 실제 사용 경로에서 확인한 것이다. 대신 확인한 것과 결론 없는 확인은 미확인이다 | 문구(`implementing-with-tdd`의 "완료 근거", Orchestrator 4절), 독립 검증 | 작성자는 의도한 것을 확인하고, 단위 테스트 통과는 기능 동작을 보이지 않는다(시험 2에서 실사용 경로로만 결함 적발) | 판정 ISSUES 중 작성자가 실사용 경로를 확인했다고 보고한 비율을 본다 |
| 최종 완료 전에 완료 조건을 기본 브랜치에서 확인하고 작업·세션·대기를 정산한다 | 문구(Orchestrator 8절) | 워커 보고의 합은 기본 브랜치의 상태가 아니다. 버리거나 흡수한 작업이 기록 없이 사라진다 | 완료 보고 뒤 사용자가 찾은 누락 수를 본다 |
| 관문과 워커의 회귀 확인은 바꾼 코드와 그 의존 범위로 한정하고, 전체 회귀는 병합 뒤 기본 브랜치에서 한 번(연달은 병합을 덮어) 돈다 | `HERDR_CHECK_AFFECTED_CMD`·`herdr-check --affected`(끝 코드 4면 전체), `herdr-report`의 병합 뒤 검사(프로젝트에 하나씩, 실패를 Orchestrator에 알림), 문구(워커, Orchestrator 3절 검증 명령, `implementing-with-tdd`) | 셸 스크립트 하나를 더한 작업에도 전체 회귀(go test 3회, books 테스트, web 게이트, 작업당 15~20분)가 관문과 병합에서 거듭 돌았다(zip-viewer checks.tsv, 2026-11-09~10) | `herdr-flow`의 작업당 검사 시간과 병합 뒤 전체 검사 FAIL 수를 본다. FAIL이 잦으면 영향 검사 명령의 의존 범위를 넓힌다 |
| 작업마다 등급(경량·일반)을 정하고, 경량은 바뀐 파일 검사만 하고 독립 검증·TDD·뮤테이션을 하지 않는다. 병합 뒤 전체 검사는 뒤에서 돈다 | `[배정]`의 `등급: 경량`을 hook이 기록, `herdr-report`·`herdr-check --light`(바뀐 줄 상한·금지 경로를 넘으면 전체 검사), 문구(Orchestrator 3절, 워커 "경량 작업", `implementing-with-tdd`) | 단순 래퍼 스크립트와 경로 이동에 전체 검사와 독립 검증을 거듭해 수 시간과 토큰을 썼다(zip-viewer U-R4·U-R5·U-R6, 2026-11-09~10, 사용자가 직접 축소 지시) | `herdr-flow`로 경량 작업의 배정→병합 시간과 병합 뒤 전체 검사 FAIL 수를 본다. FAIL이 잦으면 기준을 좁힌다 |
| Orchestrator는 Commander가 있을 때만 띄운다. 보고가 Commander에 닿지 않으면 파일에 남기고 사용자에게 알린다 | 실행기(`herdr-session`)가 `role=commander` 없이는 거부(`--no-commander`는 감시자·시험용), `herdr-report`가 `pending-decisions.md`와 `herdr-notify`, Commander 시작 hook이 남은 보고를 먼저 전하게 함, 감시자가 다시 알림 | 실행기 밖에서 연 Commander는 라벨이 없어 결정 요청이 파일에만 쌓였고 27시간 멈췄다(ohmystock 2026-11-11~12, E1·E3) | `notify.log`와 `pending-decisions.md`에 남은 요청이 사용자 답까지 걸린 시간을 본다 |
| 사용자가 화면 앞에 없어도 `[차단]`·`[완료]`를 안다 | `herdr-report`가 `HERDR_NOTIFY_TAGS`의 말머리를 `herdr-notify`로도 보냄 | Commander 화면의 질문은 사용자가 볼 때까지 기다린다 | 알림을 끄고 결정 대기 시간을 비교한다 |
| 세션·무거운 검사·검증 서브에이전트는 각자 cgroup에서 돌고, 무거운 것에는 메모리 상한을 둔다 | `herdr-scope`(systemd 사용자 scope, `HERDR_HEAVY_MEM_MAX`·`HERDR_SESSION_MEM_MAX`), 템플릿의 시작 가드 기본값(`HERDR_HEAVY_MIN_MEM_GB=4`, `HERDR_HEAVY_MAX_LOAD=auto`) | 모든 세션과 검사가 hc holder 유닛 하나에 있어 systemd-oomd가 214개를 한꺼번에 죽였다(ohmystock 2026-11-12 02:54, 유닛 peak 25.8G, 가드 0) | `journalctl --user`의 oomd 기록이 holder 대신 한 scope를 고르는지, `holder_lost` 수를 본다 |
| Orchestrator가 비정상으로 끝나면 사람 없이 다시 뜬다. 처리되지 않은 `[CLEAR 요청]`은 감시자가 대신 정리한다 | `herdr-watch`(hc 밖 systemd 서비스, `holder_lost`·SIGKILL만, 한 시간 상한, `HERDR_CLEAR_TIMEOUT`), `herdr-clear` | 복구가 사용자가 우연히 있을 때만 됐고(E2), Orchestrator의 정리가 Commander에 묶여 새 배정이 멈췄다(E6) | `watch.log`의 재기동 중 다시 같은 이유로 끝난 비율을 본다 |
| Orchestrator는 정리를 기다리는 동안에도 같은 묶음의 배정과 병합 지시를 계속한다 | 소프트 신호 hook 문구, `managing-session-context` | 정리 대기로 새 배정을 미뤄 워커가 놀았다(E6) | 신호 뒤 정리까지 워커가 쉰 시간을 본다 |
| 검증 도구가 판정 없이 끝난 것(ERROR)은 판정·횟수가 아니다 | `herdr-verify`(ERROR 기록, `HERDR_VERIFY_MAX_ERRORS`, 앞 기록을 글자 단위로 자르고 프롬프트의 잘못된 UTF-8을 버림) | 앞 기록을 바이트로 잘라 한글이 끊기자 codex가 1초 만에 거절했고, 그것이 횟수에 들어가 작업이 [차단]됐다(ohmystock 2026-11-12, E5, 3회) | verdicts.tsv의 ERROR 비율을 본다 |
| 검증 도구 한도가 모자라면 대체 도구로 바꾸거나 알린다 | `herdr-verify`(codex rollout의 `rate_limits`, `HERDR_VERIFIER_LIMIT_PCT`, `HERDR_VERIFIER_FALLBACK_*`) | 한도 98%에서 검증·병합이 사용자 답까지 멈췄다(E4) | 한도 보류 횟수와 대체 도구 판정의 오탐 비율을 본다 |
| 디스크 여유가 모자라면 하네스 캐시부터 지우고, 그래도 모자라면 검사를 보류한다 | `herdr-check`(`HERDR_MIN_DISK_GB`, 끝 코드 5), `herdr-clean` | 디스크가 1.1GB까지 줄어 사용자 승인이 필요한 docker 정리까지 갔다(E1) | 보류 횟수와 `herdr-clean`이 되찾은 크기를 본다 |
| Commander의 메시지에는 하네스가 시각을 붙이고, Claude 세션에 esc를 두 번 보내지 않는다 | `herdr-tell`, `herdr-report`의 보낸 시각, `herdr-clear`, 문구 | Commander가 결정 시각을 추측해 적었고, 입력창을 비우려던 esc esc가 되감기 창을 열었다(ohmystock 2026-11-12) | 메시지 시각 오기와 되감기 사고를 센다 |
| 사용자 결정은 그 결정이 필요한 단계만 막는다 | 문구 | 결정에 걸린 작업도 대부분은 선택지와 무관하다(크기 예산 사례) | 결정 대기 중 진행한 일이 결정 뒤 버려진 비율을 본다 |
| 재현한 결함만 막는다 | 문구 | 리뷰어는 항상 뭔가 찾아내 과잉 수정을 부른다 | 후속 제안 중 나중에 실제 결함이 된 비율을 본다 |
| 사용자 승인 기준 | 문구 | 되돌리기 어려운 행동은 사람이 정한다 | 빼지 않는다 |

## 독립 검증 시험

출처는 [pstack](https://github.com/cursor/plugins/tree/main/pstack)의 작성자·판정자 분리다. 공식 문서의 [Opus 5 안내](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5)는 별도 검증 단계를 없애라고 하고, [Claude Code 안내](https://code.claude.com/docs/en/best-practices)는 새 리뷰어가 도움이 된다고 한다. 어느 쪽도 수치가 없어 시험으로 정한다.

- 기록: `docs/status/decisions.tsv`의 판정 줄, 핸드오프 폴더의 `verdicts.tsv`와 `verify/` 검증 기록(2026-11-10부터. 그 전은 `docs/progress/`의 검증 기록).
- 2026-11-10부터 검증 세션 대신 워커가 띄우는 검증 서브에이전트로 바꿨다. 아래 시험 결과는 검증 세션 시기의 것이다.
- 유지 조건: 검증이 사람이 병합 뒤 찾았을 결함을 막았다.
- 축소 조건: 같은 유형의 묶음에서 첫 판정이 5번 연속 `PASS`다. `BLOCKED`는 세지 않는다. 5는 시작 값이며 근거가 있는 수치가 아니다.

### 시험 결과 (2026-11-07)

임시 프로젝트에서 Commander, Orchestrator(Sonnet), 작성 워커(Haiku low), 검증자(Codex gpt-6-luna low)를 실제 세션으로 돌렸다. 판정 4건은 진짜 결함 적발 1건, 오탐 1건, `PASS` 2건이다.

| 시험 | 조건 | 판정 | 결과 |
| --- | --- | --- | --- |
| 1, L-01 | 주석은 파일 저장이라 하고 코드는 메모리에만 두는 코드에 Haiku가 구현 | `ISSUES` | 오탐. 움직이는 `main`과 비교해 상태판 커밋이 범위 위반으로 잡혔다. 구현 자체는 맞았다 |
| 1, L-02 | 새 파일 추가 | `PASS` | 맞음 |
| 2, 첫 판정 | 단위 테스트는 통과하고 다른 프로세스의 `list`는 비는 커밋을 심고 "위험 없음" 보고와 함께 넘김 | `ISSUES` | 실제 사용 경로를 실행해 적발, 작성 세션이 보완 |
| 2, 재판정 | 보완 커밋 | `PASS` | 병합 뒤 main에서 `add` 2번과 `list`로 재확인 |

시험에서 고친 규칙은 다음과 같다.

- 시험 1에서 Orchestrator가 `ISSUES`를 스스로 오탐으로 판단해 병합했다. 결론은 맞았지만 절차를 벗어났다. 판정을 직접 뒤집지 않는 규칙을 넣었다. 이 규칙은 아직 실행되지 않았다.
- 범위 비교 기준을 분기점 SHA로 고쳤다. 시험 2에서 오탐이 재발하지 않았다.
- 시험 1에서 `PASS`가 결정 기록에 빠지고 `ts`가 날짜뿐이었다. 규칙을 고친 뒤 시험 2에서 재발하지 않았다.
- 시험 2에서 `[검증]`에 작성자 worktree가 적혀 검증자가 거기서 실행했다. 메시지에서 뺐다. 이 수정은 다시 시험하지 않았다.

이 시험으로 알 수 없는 것은 다음과 같다.

- 시험 2의 결함은 직접 심었고, 실제 작성 워커가 만든 결함을 잡은 사례는 아직 없다. 시험 1의 Haiku는 틀린 주석이 있어도 맞게 구현했다.
- 대조군이 없다. 시험 2의 보고는 단위 테스트만 근거로 들어, Orchestrator의 근거 대조만으로 걸러졌을 수도 있다.
- 비용은 재지 않았고, 묶음은 2개뿐이라 유지·축소를 판단할 표본이 아니다.

## pstack에서 가져온 것

[pstack](https://github.com/cursor/plugins/tree/main/pstack)(2026-11-06 기준)을 두 번 검토했다. 첫 검토(2026-11-07)에서 작성자·판정자 분리, 시작 계약, 결정 기록, 규칙과 강제 수단 표를 가져왔다. 두 번째 검토(2026-11-10)에서 가져온 것은 다음과 같다.

| 출처 | 들어간 곳 |
| --- | --- |
| prove-it-works, 검증 가이드(06-verify-and-ship), bug-fix·feature 플레이북의 "다른 경로·결론 없는 확인은 통과가 아니다" | `implementing-with-tdd`의 "완료 근거", `AGENTS.core.md`의 완료 |
| shipping 플레이북의 patch-id로 판정 유지 | `worker.md`의 "병합" |
| orchestrate 플레이북의 "요약이 아니라 결과물을 읽는다", "지금 상태로 보고한다", "띄운 작업을 모두 정산한다" | `orchestrator.md` 4절, 8절 |
| feature·refactoring·bug-fix 플레이북, architect의 설계 경고 신호, 원칙(model-the-domain, boundary-discipline, make-operations-idempotent, separate-before-serializing-shared-state, fix-root-causes, attack-the-premise, test-behavior-not-implementation, build-the-lever, sequence-verifiable-units, subtract-before-you-add, migrate-callers-then-delete-legacy-apis, minimize-reader-load, explain-the-number) | `implementing-with-tdd` |

2026-11-10에 독립 검증을 검증 세션에서 서브에이전트로 바꾸면서, 검증에 한해 pstack처럼 매번 새 맥락으로 띄운다(`herdr-verify`). 판정자가 앞 판단과 작성자의 맥락에 묶이지 않아야 하고, 검증 세션은 대기열과 중계를 만들었기 때문이다. 구현은 그대로 세션 재사용이다.

가져오지 않은 것: 구현 작업마다 새 서브에이전트를 띄우는 방식(이 하네스는 맥락을 이어받는 세션 재사용을 시험 중이다), 모델 경쟁(arena·swarm·interrogate의 다중 모델, 비용), PR·CI·봇 처리 플레이북(이 하네스는 로컬 병합이다), Cursor 전용 기능.
