# myharness

herdr로 개발을 자율주행하는 기본 동작만 담은 하네스다. 사용자가 목표를 주면 세션들이 계획·배정·구현·검증·병합을 이어 가고, 사용자 결정이 필요할 때만 멈춘다. Codex와 Claude Code에서 함께 쓴다.

## 담은 것

| 스킬 | 내용 |
| --- | --- |
| `running-herdr-autopilot` | Commander·Orchestrator·워커 역할, 의존성·맥락 연관도 기반 배정, 서브에이전트 사용 범위 |
| `managing-session-context` | 작업 경계의 `/clear`, 작업 중 auto-compact, 소프트 신호, compact 후 복구 |
| `writing-project-docs` | 방향 문서, 개발 과정 기록, 작업 계획·상태판, 문서 분할·색인 |

그 밖에 세션 실행기와 보고 명령(`core/bin/`), 역할 주입·컨텍스트·보고 누락 방지 hook(`core/hooks/`), 프로젝트 템플릿(`templates/`)이 있다. 린트·테스트 자동화, TDD 절차, 언어별 설정은 담지 않는다. 프로젝트가 `AGENTS.md`의 검사 명령과 전용 스킬로 더한다.

컨텍스트 정책의 근거와 검증 결과는 [docs/context-policy.md](docs/context-policy.md), 규칙별 강제 수단과 전제, 독립 검증 시험은 [docs/rules-and-enforcement.md](docs/rules-and-enforcement.md)에 있다.

## 시작

### 1. 필요한 도구 설치

필요한 것: `hc`(herdr-core), `jq`, `git`, `rsync`, `claude` 또는 `codex`.

`hc`는 herdr 앱과 따로 설치한다. herdr 앱은 hc(herdr-core) 위의 클라이언트 중 하나일 뿐이라, herdr 앱만 있으면 `hc` 명령이 없다. 실행기·보고 명령·스킬의 세션 띄우기, 라벨, 메시지가 모두 `hc`를 쓴다.

```bash
curl -fsSL https://releases.herdr.dev/core/install.sh | sh   # ~/.local/bin/hc 에 설치된다
hc --version                                                  # 예: hc 0.1.18. 안 나오면 ~/.local/bin 을 PATH에 넣는다
```

### 2. 프로젝트에 하네스 설치

새 프로젝트는 `init`, 이미 설치한 프로젝트는 `sync`로 실행기를 최신으로 맞춘다. 예전 실행기는 herdr 패널에서 `--here`를 거부한다.

```bash
bin/harness init <프로젝트 경로>    # 처음 설치
bin/harness sync <프로젝트 경로>    # 이미 설치한 프로젝트 갱신
```

설치한 뒤 다음을 채운다.

- `intent.md`와 `AGENTS.md`의 "프로젝트 규칙"
- `.agents/harness.env`: `HERDR_AUTONOMOUS=1`은 권한 확인 없이 도는 모드다. 운영 자원이나 비밀에 닿는 프로젝트는 0으로 둔다.

### 3. herdr 패널에서 Commander 띄우기

herdr 화면에서 패널을 하나 열고, 프로젝트 폴더로 가서 실행한다.

```bash
cd <프로젝트 경로>
.agents/bin/herdr-session --here commander codex    # Claude를 쓰면 마지막을 claude로
```

실행하면 다음이 일어난다.

1. herdr 패널은 hc 터미널이 아니므로 실행기가 `hc run --bg`로 hc 터미널을 새로 열어 `role=commander`, `project=<프로젝트 폴더 이름>` 라벨을 붙이고, 이 패널을 `hc attach`로 거기에 붙인다. 이미 hc 터미널 안에서 실행했다면 새로 열지 않고 지금 터미널에 라벨을 붙인다.
2. 그 안에서 codex(또는 claude)가 프로젝트 폴더를 작업 위치로 해서 뜬다.
3. 새 폴더에서 처음 띄우면 폴더 신뢰 확인 창이 뜬다. codex는 `1. Trust and continue`, claude는 `Yes, I trust this folder`를 골라 한 번 승인한다. 이후 같은 폴더에 뜨는 세션은 묻지 않는다. codex는 이보다 먼저 업데이트 안내를 띄울 수 있다.

### 4. 목표 말하기

Commander에게 목표를 말한다. Orchestrator가 없으면 Commander가 띄우고, 워커는 Orchestrator가 띄운다. 둘 다 실행기로 띄우므로 사용자가 직접 띄울 필요는 없다.

### 떠나기, 다시 붙기, 끝내기

Commander는 herdr 패널이 아니라 hc 터미널에서 돈다. 그래서 패널을 닫거나 `ctrl+\`로 떨어져도 세션은 계속 돈다.

```bash
hc ls --label "project=<프로젝트 폴더 이름>"                       # 이 프로젝트의 세션 목록. 맨 앞이 주소(예: t3)
hc ls --label "project=<프로젝트 폴더 이름>" --label role=commander  # Commander만
hc attach t3                                                       # 다시 붙기. ctrl+\ 로 떨어진다
hc kill t3                                                         # 세션 끝내기
```

## 갱신

```bash
bin/harness sync <프로젝트>
```

스킬 3개, 실행기, hook, `AGENTS.md`의 표시 블록만 덮어쓴다. 프로젝트 전용 스킬, `harness.env`, `intent.md`, 문서는 그대로 둔다. 파일은 전역이 아니라 프로젝트 안에 설치되므로, 커밋 전에 `git diff`로 바뀐 내용을 확인한다.

## 문제 해결

| 증상 | 원인과 조치 |
| --- | --- |
| `--here 는 herdr 터미널 안에서만 쓴다` | 예전 실행기다. herdr 패널은 hc 터미널이 아니라서 거부했다. `bin/harness sync <프로젝트 경로>`로 실행기를 갱신한다 |
| `hc(herdr-core)가 없다` | `hc`가 설치되지 않았거나 PATH에 없다. 위 설치 명령을 실행하고 `hc --version`으로 확인한다 |
| `command not found: hc` | 위와 같다. 설치 위치 `~/.local/bin`을 PATH에 넣는다 |
| `--here`로 띄웠는데 화면이 멈춘 채 아무것도 안 나온다 | `--bg` 없는 `hc run`으로 띄우던 이전 실행기다(끝날 때까지 기다렸다가 출력만 보여 준다). `bin/harness sync`로 갱신한 뒤 다시 띄운다. 이미 뜬 세션은 `hc attach <주소>`로 붙거나 `hc kill <주소>`로 끝낸다 |
| 패널을 닫았더니 Commander가 사라진 것 같다 | 세션은 hc 터미널에 남아 있다. `hc ls --label "project=<프로젝트 폴더 이름>"`로 찾아 `hc attach`로 붙는다 |
| codex가 띄운 명령이 hc 밖에서 돈다 | 실행기가 codex에 `--no-daemon`을 붙인다. 예전 실행기면 `bin/harness sync`로 갱신한다 |

## 구조

```
core/                 프로젝트에 복사되는 원본
  AGENTS.core.md      AGENTS.md 표시 블록에 들어가는 규칙과 스킬 표
  skills/             스킬 3개
  bin/herdr-session   세션 실행기, 세션별 모델 표의 원본
  bin/herdr-report    보고 명령
  hooks/              역할 주입·compact 복구, 소프트 신호, compact 직전 스냅샷, 보고 누락 방지
  config/             Claude·Codex hook 설정
templates/            init 때 한 번만 넣는 파일
bin/harness           init, sync
tests/smoke.sh        설치·hook·실행기의 기계적 확인
```

## 전역 지침과의 관계

전역 `operating-herdr-sessions`와 전역 컨텍스트 hook은 진행 중인 다른 프로젝트가 쓰고 있어 바꾸지 않았다. 이 하네스를 설치한 프로젝트에서는 다음과 같이 대체한다.

- 세션이 시작되거나 `/clear`될 때마다 hook이 역할과 읽을 파일 경로를 주입한다. `AGENTS.md`의 안내만으로는 부족했다(시험에서 워커가 전역 스킬을 읽고 옛 규칙으로 일했다).
- 실행기가 `HERDR_CTX_GUARD_OFF=1`로 전역 hook의 알림을 끈다. 그래서 세션은 반드시 실행기로 띄운다.

스킬 이름은 전역 스킬과 겹치지 않게 지었다. Claude Code는 같은 이름이면 개인 스킬을 프로젝트 스킬보다 우선한다.

## 테스트

```bash
tests/smoke.sh
```

전역과 실제 세션을 건드리지 않는다. Linux(GNU)와 macOS(BSD) 도구 모두에서 돈다. `hc`는 가짜로 대신하므로 설치하지 않아도 된다. 실제 세션 동작은 [docs/context-policy.md](docs/context-policy.md)의 "검증 결과"처럼 도구 버전이 바뀔 때 다시 확인한다.
