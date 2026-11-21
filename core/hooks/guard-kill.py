#!/usr/bin/env python3
"""넓은 패턴으로 프로세스를 죽이는 명령을 막는다(PreToolUse, Bash). 끝 코드 2와 stderr로 에이전트에게 돌려준다.

같은 기계에는 다른 세션·프로젝트의 검사와 세션 프로세스가 함께 돈다. 세션 프로세스의 명령줄에는 첫 임무 원문이 들어 있어
`pkill -f "herdr-queue run --role"` 같은 패턴이 다른 세션 자체에도 맞는다. 막는 것은 이름·패턴으로 고르는 kill이다.
  막는다: pkill, killall, pgrep·pidof·ps 결과를 kill에 넘기는 명령($(...), 파이프로 xargs kill)
  통과한다: PID로 죽이는 kill, pkill -P <PID>, 이 worktree 경로(저장소 최상위 경로 아래)를 패턴에 넣은 pkill·pgrep
          (메인 체크아웃 경로는 세션의 명령줄에도 들어 있어 통과시키지 않는다)
역할이 없는 세션(HERDR_ROLE 없음)이나 입력을 읽지 못하면 조용히 넘어간다.
"""
import json
import os
import re
import shlex
import subprocess
import sys

BROAD_USER_OPTS = {"-u", "-U", "--euid", "--uid"}
WRAPPERS = ("sudo", "env", "nohup", "time", "exec", "command", "nice", "setsid", "stdbuf", "busybox")


def linked_worktree_root(cwd):
    """cwd가 딸린(linked) worktree이면 그 최상위 경로, 메인 체크아웃이거나 git 밖이면 None."""
    def git(*args):
        r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=5)
        return r.stdout.strip() if r.returncode == 0 else ""
    top = git("rev-parse", "--show-toplevel")
    gdir = git("rev-parse", "--absolute-git-dir")
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir")
    if not top or not gdir or not common or os.path.realpath(gdir) == os.path.realpath(common):
        return None
    return os.path.realpath(top)


def narrowed(text, cwd, root):
    """패턴·파이프라인이 이 linked worktree 안의 경로(최상위 경로 자체는 제외)로 좁혀졌는가."""
    if root is None:
        return False
    for form in {root, cwd, os.path.realpath(cwd)}:
        if form and form.startswith(root) and (form + "/") in text:
            return True
    if re.search(r"\$\{?PWD\}?/\S|\$\(pwd\)/\S", text):
        return os.path.realpath(cwd).startswith(root)
    return (root + "/") in text


def mask(command):
    """heredoc 본문과 따옴표 안의 글자를 공백으로 가린다(커밋 메시지·검색어 안의 pkill을 명령으로 보지 않는다)."""
    command = re.sub(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n\s*\1\b", lambda m: m.group(0).split("\n", 1)[0], command, flags=re.S)
    return re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", lambda m: m.group(0)[0] + " " * (len(m.group(0)) - 2) + m.group(0)[-1], command)


def simple_commands(command):
    parts = re.split(r"\n|&&|\|\||[;|&]|\$\(|`|\(|\)", command)
    for part in parts:
        try:
            words = shlex.split(part)
        except ValueError:
            words = part.split()
        while words and (re.match(r"^\w+=", words[0]) or os.path.basename(words[0]) in WRAPPERS or os.path.basename(words[0]) == "timeout"):
            skip = 2 if os.path.basename(words[0]) == "timeout" and len(words) > 1 else 1
            words = words[skip:]
        if words:
            yield words


def pkill_verdict(words, text, cwd, root):
    name = os.path.basename(words[0])
    args = words[1:]
    if name == "killall":
        return None if "-l" in args else "killall은 이름이 같은 모든 프로세스를 죽인다"
    pattern_args, i, parent = [], 0, False
    while i < len(args):
        a = args[i]
        if a in BROAD_USER_OPTS:
            return "pkill -u/-U는 그 사용자의 모든 프로세스에 맞는다"
        if a == "-P" and i + 1 < len(args):
            parent, i = True, i + 2
            continue
        if a.startswith("-P") and len(a) > 2:
            parent = True
        elif a in ("-s", "-g", "-G", "-t", "-n", "-o", "--signal", "--pgroup", "--session", "--terminal"):
            i += 2
            continue
        elif not a.startswith("-"):
            pattern_args.append(a)
        i += 1
    if parent and not pattern_args:
        return None
    if not pattern_args:
        return None
    if any(narrowed(p, cwd, root) for p in pattern_args) or narrowed(text, cwd, root):
        return None
    return "패턴이 다른 세션의 프로세스나 세션 자체의 명령줄(첫 임무 원문 포함)에도 맞을 수 있다"


def verdict(command, cwd, depth=0):
    root = linked_worktree_root(cwd)
    plain = mask(command)
    for words in simple_commands(command):
        name = os.path.basename(words[0])
        if name in ("sh", "bash", "zsh") and "-c" in words and depth < 3 and words.index("-c") + 1 < len(words):
            why = verdict(words[words.index("-c") + 1], cwd, depth + 1)
            if why:
                return why
    for words in simple_commands(plain):
        name = os.path.basename(words[0])
        if name in ("pkill", "killall", "killall5"):
            # 가린 글자 때문에 패턴이 비므로 원문에서 같은 명령을 찾아 판정한다
            orig = next((w for w in simple_commands(command) if os.path.basename(w[0]) == name), words)
            why = pkill_verdict(orig, " ".join(orig), cwd, root) if name != "killall5" else "killall5는 모든 프로세스를 죽인다"
            if why:
                return f"{name}: {why}"
        if name == "kill" and re.search(r"(^|\s)-?-?\s*-1(\s|$)", " ".join(words[1:])):
            return "kill -1(PID -1)은 이 사용자의 모든 프로세스를 죽인다"
    # pgrep·pidof·ps로 고른 PID를 kill에 넘기는 명령
    lookup = r"\b(pgrep|pidof|ps)\b"
    fed = [
        re.search(r"\bkill\b[^\n;&|]*(\$\(|`)\s*[^)`]*" + lookup, plain),
        re.search(lookup + r"[^\n]*\|[^\n]*\bxargs\b[^\n]*\bkill\b", plain),
        re.search(lookup + r"[^\n]*\|[^\n]*\bwhile\b[^\n]*\bkill\b", plain),
        re.search(r"\bfor\b[^\n;]*\$\([^)]*" + lookup + r"[^)]*\)[^\n]*\bkill\b", plain),
    ]
    for m in fed:
        if m and not narrowed(command[m.start():m.end() + 200], cwd, root):
            return "pgrep·pidof·ps로 고른 프로세스를 kill에 넘기는 명령은 패턴에 맞는 모든 프로세스를 죽인다"
    return None


def main():
    if not os.environ.get("HERDR_ROLE"):
        return 0
    try:
        data = json.load(sys.stdin)
        tool_input = data.get("tool_input") or {}
        command = tool_input.get("command") or tool_input.get("cmd") or ""
        if isinstance(command, list):
            command = " ".join(command)
        cwd = data.get("cwd") or os.getcwd()
        why = verdict(command, cwd) if command else None
    except Exception:
        return 0
    if not why:
        return 0
    sys.stderr.write(
        f"막음: {why}.\n"
        "- 내가 띄운 프로세스: 그 PID로 kill <PID> (백그라운드로 띄웠으면 $!로 PID를 받아 둔다).\n"
        "- 내가 대기열에 넣은 검사: herdr-queue cancel (이 세션의 프로젝트·역할 것만 멈춘다).\n"
        "- 이름으로 꼭 찾아야 하면 이 worktree 경로까지 넣어 좁힌다: pkill -f \"$PWD/…\" (메인 체크아웃 경로는 안 된다).\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
