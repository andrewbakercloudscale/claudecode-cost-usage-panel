# Check AF -- a claude with no pane writes no pin.
#
# Check AA is about the KEY a pin is stored under. This one is about who is
# allowed to write one at all.
#
# The SessionStart hook fires for every session Claude Code starts, and most
# of them are not sessions anyone is looking at: `claude --print` is how the
# standards-review sections run, how build scripts shell out to the CLI, how
# a hook spawns a one-shot. Each of those got a session id, a transcript in
# the project directory, and -- until 2026-09-14 -- a pin.
#
# Observed that afternoon in wordpress-backup-restore-plugin. A build ran two
# review sections at 16:14:30; both wrote the directory pin; the panel beside
# a 1080-turn Opus session adopted the second one three seconds later and
# spent the rest of the afternoon reporting a 7-turn Sonnet review as this
# pane's session -- "Model: Sonnet 5", $0.30, 9% context, a three-row turn
# table -- while the session it was watching ran on at $38/hr beside it. The
# model line is what gave it away; every other figure was wrong in exactly
# the same way and looked plausible.
#
# The tty pin was worse and had not been noticed at all. The hook found its
# terminal by walking up the ancestry to the first process that had one,
# which for a headless claude is not the claude -- it is the interactive
# shell that started the build, several levels further up. So a throwaway
# `--print` session wrote a PANE pin against the pane of the session that
# launched it: the strongest channel there is, pointed at the wrong session,
# by an ordinary build.
#
# The ancestry is stubbed here rather than built for real. A check cannot
# spawn a headless claude under a terminal-less parent without spawning
# claude, and what is being tested is the walk, not the process tree.
check_AF_headless_pin() {
  sandbox_new AF
  local hook="$HOME_REAL_BIN/claude-panel-session-hook.sh"
  if [ ! -f "$hook" ]; then
    assert_eq "session hook is present to be checked" "1" "0"
    return
  fi

  local bin pindir sid payload
  bin="$SBX/bin"
  pindir="$SBX/pin"
  mkdir -p "$bin" "$pindir"
  sid="abcdabcd-1111-2222-3333-444444444444"
  payload='{"session_id":"'"$sid"'","cwd":"/Users/x/repo"}'

  # `ps` answering from a fixture: PS_CHAIN is "pid:ppid:tty:comm" entries,
  # and any pid not in it is the hook itself (which never has a terminal of
  # its own -- Claude Code hands it pipes).
  cat > "$bin/ps" <<'STUB'
#!/usr/bin/env bash
fmt=""; pid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) fmt="$2"; shift 2 ;;
    -p) pid="$2"; shift 2 ;;
    *) shift ;;
  esac
done
row="1000:??:bash"          # the hook process
for e in $PS_CHAIN; do
  case "$e" in
    "$pid":*) row="${e#*:}"; break ;;
  esac
done
IFS=: read -r pp tt cc <<<"$row"
case "$fmt" in
  ppid=) printf '%s\n' "$pp" ;;
  tty=)  printf '%s\n' "$tt" ;;
  comm=) printf '%s\n' "$cc" ;;
esac
STUB
  chmod +x "$bin/ps"

  local dirpin ttydir log
  dirpin="$pindir/-Users-x-repo"
  ttydir="$pindir/tty"
  log="$HOME/.cache/claude-panel-pin.log"

  # ---- 1. the observed case: `claude --print` inside an interactive session
  # The headless claude is pid 1000 with no terminal; ttysREAL two levels up
  # belongs to the pane that ran the build, and is the terminal the old walk
  # returned.
  PATH="$bin:$PATH" PANEL_PIN_DIR="$pindir" \
    PS_CHAIN="1000:1001:??:claude 1001:1002:ttysREAL:bash 1002:1:ttysREAL:claude" \
    bash "$hook" <<<"$payload"
  assert_eq "a headless claude writes no directory pin" "0" "$([ -e "$dirpin" ] && echo 1 || echo 0)"
  assert_eq "and no pane pin against the terminal that launched it" \
    "0" "$([ -e "$ttydir/ttysREAL" ] && echo 1 || echo 0)"
  # Silently doing nothing is the other half of this failure mode: say so.
  assert_contains "and says in the log why it wrote nothing" \
    "no pin written" "$(cat "$log" 2>/dev/null)"

  # ---- 2. an ordinary pane still pins, both ways ------------------------
  rm -f "$log"
  PATH="$bin:$PATH" PANEL_PIN_DIR="$pindir" \
    PS_CHAIN="1000:1001:ttysPANE:claude 1001:1:ttysPANE:bash" \
    bash "$hook" <<<"$payload"
  assert_eq "a claude in a pane writes the directory pin" "$sid" "$(cut -f1 "$dirpin" 2>/dev/null)"
  assert_eq "and the pane pin for its own terminal" "$sid" "$(cut -f1 "$ttydir/ttysPANE" 2>/dev/null)"

  # ---- 3. a wrapper shell between the hook and claude costs nothing -----
  # Why the walk exists at all: $PPID is not reliably claude.
  rm -rf "$pindir"; mkdir -p "$pindir"
  PATH="$bin:$PATH" PANEL_PIN_DIR="$pindir" \
    PS_CHAIN="1000:1001:??:sh 1001:1002:ttysPANE:claude 1002:1:ttysPANE:bash" \
    bash "$hook" <<<"$payload"
  assert_eq "a wrapper shell does not hide the pane" "$sid" "$(cut -f1 "$ttydir/ttysPANE" 2>/dev/null)"

  # ---- 4. no claude in the ancestry at all ------------------------------
  # Nothing to attribute the session to, so nothing is claimed -- the same
  # answer as the headless case, reached a different way.
  rm -rf "$pindir"; mkdir -p "$pindir"
  PATH="$bin:$PATH" PANEL_PIN_DIR="$pindir" \
    PS_CHAIN="1000:1001:ttysREAL:bash 1001:1:ttysREAL:login" \
    bash "$hook" <<<"$payload"
  assert_eq "an unattributable session claims no pane" \
    "0" "$([ -e "$ttydir/ttysREAL" ] && echo 1 || echo 0)"
  assert_eq "and no directory pin either" "0" "$([ -e "$pindir/-Users-x-repo" ] && echo 1 || echo 0)"
}
