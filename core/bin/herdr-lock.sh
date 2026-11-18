# shellcheck shell=bash
# 하네스 잠금(source 해서 쓴다). flock 이 없는 맥에서도 걸리게 폴더 만들기(mkdir — 한 번에 하나만 성공)로 잠근다.
# 잠금 = <경로>.lockd 폴더, 안의 pid 에 쥔 프로세스 번호($$). 그 프로세스가 없으면 버려진 잠금으로 보고 걷는다.
# herdr_lock <경로> [try]  쥘 때까지 기다린다(try 면 못 쥐면 바로 1). herdr_unlock <경로>  자기 것일 때만 푼다.
# herdr_lock_busy <경로>   살아 있는 프로세스가 쥐고 있으면 0.
herdr_lock() {
  local lk="$1.lockd" holder said=""
  while ! mkdir "$lk" 2>/dev/null; do
    holder="$(cat "$lk/pid" 2>/dev/null)"
    # 번호가 없으면 막 만든 중이거나 적기 전에 죽은 것이다. 1분이 지나도 없으면 버려진 것으로 본다
    if { [[ -n "$holder" ]] && ! kill -0 "$holder" 2>/dev/null; } || { [[ -z "$holder" && -n "$(find "$lk" -maxdepth 0 -mmin +1 2>/dev/null)" ]]; }; then
      echo "버려진 잠금을 걷는다(쥔 프로세스 ${holder:-번호 없음}이 없다): $lk" >&2
      mv "$lk" "$lk.stale.$$" 2>/dev/null && rm -rf "$lk.stale.$$"
      continue
    fi
    [[ "${2:-}" == try ]] && return 1
    [[ -z "$said" ]] && { said=1; echo "잠금을 쥔 프로세스 ${holder:-?}가 끝나기를 기다린다: $lk" >&2; }
    sleep 2
  done
  echo $$ >"$lk/pid"
}
herdr_unlock() { [[ "$(cat "$1.lockd/pid" 2>/dev/null)" == "$$" ]] && rm -rf "$1.lockd"; return 0; }
herdr_lock_busy() { local h; h="$(cat "$1.lockd/pid" 2>/dev/null)"; [[ -n "$h" ]] && kill -0 "$h" 2>/dev/null; }
