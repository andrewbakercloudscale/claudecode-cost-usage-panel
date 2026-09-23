# Check AL -- a new session is titled after its folder, and only a new one.
#
# Without a session title Claude Code titles every terminal window "Claude
# Code", so several open sessions are indistinguishable in the window
# switcher. The SessionStart hook names the session after the folder through
# hookSpecificOutput.sessionTitle. It must do so on "startup" only: a resumed
# session may carry a title chosen with /rename, and the folder name would
# silently overwrite it.
check_AL_session_title() {
  sandbox_new AL
  local hook="$HOME_REAL_BIN/claude-panel-session-hook.sh"
  if [ ! -f "$hook" ]; then
    assert_eq "session hook is present to be checked" "1" "0"
    return
  fi

  local sid out
  sid="abcdabcd-1111-2222-3333-444444444444"
  run_hook() {
    printf '{"session_id":"%s","cwd":"/Users/x/my-repo","source":"%s"}' "$sid" "$1" |
      PANEL_PIN_DIR="$SBX/pin" bash "$hook" 2>/dev/null
  }

  out=$(run_hook startup)
  assert_eq "startup: title is the folder name" \
    "my-repo" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.sessionTitle // "none"' 2>/dev/null)"
  assert_eq "startup: output names the SessionStart event" \
    "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // "none"' 2>/dev/null)"

  out=$(run_hook resume)
  assert_eq "resume: prints nothing (keeps a /rename title)" "" "$out"
  out=$(run_hook clear)
  assert_eq "clear: prints nothing" "" "$out"
  out=$(env PANEL_SESSION_TITLE=0 bash -c 'printf "%s" "$0" | PANEL_PIN_DIR="$1" bash "$2"' \
    '{"session_id":"'"$sid"'","cwd":"/Users/x/my-repo","source":"startup"}' "$SBX/pin" "$hook" 2>/dev/null)
  assert_eq "PANEL_SESSION_TITLE=0: prints nothing" "" "$out"
}
