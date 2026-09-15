# Check AI -- the pane a panel is in is a fact about the process tree, and a
# session is over when its process is gone, not when its transcript goes
# quiet.
#
# Checks AA, AF and AG built the pin up to here: keyed on the pane, written
# only for a claude that has one, and dropped once the session it names is
# over. All three were in place on 2026-09-15 and the panel beside a live
# session still went blank for eighteen minutes and then reported a session
# from another window, because both remaining answers were indirect:
#
#   * WHICH PANE. The pairing comes from a file the launcher writes after it
#     has spotted the panel in a `pgrep`, and when that misses there is no
#     second try -- the panel spends its whole life on the directory-keyed
#     pin, which names a REPO. Two of the three panels open in this repo that
#     morning had no pairing file at all, and `ps` says why they did not need
#     one: panel 55120 and claude 54674 both descend from Ghostty window
#     54665; panel 77229 and claude 77051 both descend from window 77030. The
#     panes are paired in the process tree whether or not anyone writes it
#     down.
#
#   * WHETHER IT IS OVER. PIN_DEAD_SECS measured the transcript's mtime, and
#     a transcript stops growing the moment a session stops being TYPED into.
#     At 10:29:13 both panels dropped a session that had last been typed to
#     at 09:59 -- `claude` pid 54674 was running then and is running now --
#     showed "no active Claude Code session found" until 10:47:04, and then
#     adopted a session belonging to a different pane. The release added to
#     prevent a misattribution caused one.
check_AI_window_pairing() {
  sandbox_new AI
  local proj dirpin ttydir panedir mine theirs turn
  proj="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  dirpin="$HOME/.cache/claude-panel-pin/$(printf '%s' "$PWD" | tr '/' '-')"
  ttydir="$HOME/.cache/claude-panel-pin/tty"
  panedir="$HOME/.cache/claude-panel-pin/pane"
  mkdir -p "$proj" "$ttydir" "$panedir"
  turn='{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}'
  mine="11111111-1111-2222-3333-444444444444"
  theirs="22222222-1111-2222-3333-444444444444"
  printf '%s\n' "$turn" > "$proj/$mine.jsonl"
  printf '%s\n' "$turn" > "$proj/$theirs.jsonl"

  local pin src ctty got

  # ---- 1. the window answers what the launcher failed to write ----------
  # No pairing file, and a directory pin naming the OTHER session, written
  # seconds ago so every freshness test it has passes. Both sessions have a
  # tty pin, so the sole-live recovery cannot break the tie either: without
  # the window walk this panel follows the other pane, which is what the two
  # panels in the incident did.
  printf '%s\t%s\n' "$theirs" "$(date +%s)" > "$dirpin"
  printf '%s\t%s\n' "$mine"   "$(date +%s)" > "$ttydir/ttyMINE"
  printf '%s\t%s\n' "$theirs" "$(date +%s)" > "$ttydir/ttyTHEIRS"
  fake_ps_reset
  fake_ps_window 9000 ttyMINE "$mine" "$$" ttyPANEL
  (
    PANEL_PANE_TTY=ttyPANEL load_panel 10 12
    resolve_session
    printf '%s|%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$PANE_CLAUDE_TTY" "$latest"
  ) > "$TEST_TMP/AI.window"
  IFS='|' read -r pin src ctty got < "$TEST_TMP/AI.window"
  assert_eq "the claude in this panel's own window is found" "ttyMINE" "$ctty"
  assert_eq "and its session is preferred to the directory pin" "$mine" "$pin"
  assert_eq "and is recorded as coming from the pane" "pane" "$src"
  assert_eq "and resolves this pane's transcript" "$proj/$mine.jsonl" "$got"

  # ---- 2. a second claude in the window is ambiguity, not an answer -----
  # Same rule as two live pane sessions in one repo: pair nothing rather than
  # pick, and leave the weaker directory pin to answer as it did before.
  fake_ps_reset
  fake_ps_window 9000 ttyMINE "$mine" "$$" ttyPANEL
  fake_ps_proc 9100 9000 ttyOTHER "claude --session-id $theirs --dangerously-skip-permissions"
  (
    PANEL_PANE_TTY=ttyPANEL load_panel 10 12
    resolve_session
    printf '%s|%s\n' "$PANE_CLAUDE_TTY" "$PIN_SOURCE"
  ) > "$TEST_TMP/AI.two"
  IFS='|' read -r ctty src < "$TEST_TMP/AI.two"
  assert_eq "two claude panes in one window pair nothing" "" "$ctty"
  assert_ne "and the pin is not claimed to be pane-scoped" "pane" "$src"

  # ---- 3. under tmux the walk cannot answer, and says so ----------------
  # Every tmux pane descends from the one tmux SERVER, shared by every window
  # and every session on the machine, so the same walk would answer "all of
  # them". Declining there is the difference between a channel that is quiet
  # and one that is wrong.
  fake_ps_reset
  fake_ps_window 9000 ttyMINE "$mine" "$$" ttyPANEL
  (
    # Exported, not prefixed onto load_panel: the walk reads $TMUX when
    # resolve_session runs, which is after that command has returned.
    export TMUX=/private/tmp/tmux-501/default,1234,0
    PANEL_PANE_TTY=ttyPANEL load_panel 10 12
    resolve_session
    printf '%s\n' "$PANE_CLAUDE_TTY"
  ) > "$TEST_TMP/AI.tmux"
  assert_eq "inside tmux the window walk declines" "" "$(cat "$TEST_TMP/AI.tmux")"

  # ---- 4. paired, but no pin yet: the id on claude's command line -------
  # A pane that is known and a hook that has not run (or is not installed)
  # used to be the worst of both: better addressed than the directory pin,
  # and blind where the directory pin would have answered.
  rm -f "$ttydir/ttyMINE"
  fake_ps_reset
  fake_ps_window 9000 ttyMINE "$mine" "$$" ttyPANEL
  (
    PANEL_PANE_TTY=ttyPANEL load_panel 10 12
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AI.argv"
  IFS='|' read -r pin src got < "$TEST_TMP/AI.argv"
  assert_eq "the session id is read off claude's own argv" "$mine" "$pin"
  assert_eq "and still belongs to this pane" "pane" "$src"
  assert_eq "and resolves its transcript" "$proj/$mine.jsonl" "$got"
  printf '%s\t%s\n' "$mine" "$(date +%s)" > "$ttydir/ttyMINE"

  # ---- 5. a quiet transcript with a live process is not a dead pin ------
  # The 10:29:13 release, exactly: an unpaired panel (no window in the table
  # for it) holding the directory pin, whose session has not been typed into
  # for longer than PIN_DEAD_SECS and whose claude is running the whole time.
  printf '%s\t%s\n' "$mine" "$(date +%s)" > "$dirpin"
  rm -f "$ttydir/ttyTHEIRS"
  fake_ps_reset
  fake_ps_proc 9200 1 '??' "/Applications/Ghostty.app/Contents/MacOS/ghostty -e x"
  fake_ps_proc 9201 9200 ttyMINE "claude --session-id $mine --dangerously-skip-permissions"
  (
    PANEL_PANE_TTY=ttyPANEL load_panel 10 12
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE"
    age_file "$proj/$mine.jsonl" 1801
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AI.idle"
  IFS='|' read -r pin src < <(head -1 "$TEST_TMP/AI.idle")
  assert_eq "a live session is adopted from the directory pin" "$mine" "$pin"
  assert_eq "from the directory file" "handoff" "$src"
  IFS='|' read -r pin src got < <(tail -1 "$TEST_TMP/AI.idle")
  assert_eq "and kept once it goes quiet, because its process is alive" "$mine" "$pin"
  assert_eq "still from the same source" "handoff" "$src"
  assert_eq "and still resolving its transcript" "$proj/$mine.jsonl" "$got"

  # ---- 6. ...and released when nothing is running it --------------------
  # The boundary matters: check AG's release is the reason this pin mechanism
  # is trusted at all, and a liveness test that never says no would have
  # quietly repealed it.
  fake_ps_reset
  (
    PANEL_PANE_TTY=ttyPANEL load_panel 10 12
    resolve_session
    age_file "$proj/$mine.jsonl" 1801
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/AI.gone"
  IFS='|' read -r pin got < "$TEST_TMP/AI.gone"
  assert_eq "a quiet transcript with no process is released" "" "$pin"
  assert_eq "and resolves nothing" "" "$got"

  # ---- 7. recovery: the live pane session, typed into or not ------------
  # The unpaired panel's own way back, and it used to be unreachable in the
  # case that needs it most -- a panel that has just dropped a pin for half
  # an hour of quiet finds no candidate for the same reason and stays blank
  # until the person it reports on comes back. The claude here is in another
  # window, so nothing pairs; the tty pin and the process are the evidence.
  rm -f "$dirpin"
  fake_ps_reset
  fake_ps_proc 9300 1 '??' "/Applications/Ghostty.app/Contents/MacOS/ghostty -e x"
  fake_ps_proc 9301 9300 ttyMINE "claude --session-id $mine --dangerously-skip-permissions"
  age_file "$proj/$mine.jsonl" 1801
  (
    PANEL_PANE_TTY=ttyPANEL load_panel 10 12
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AI.recover"
  IFS='|' read -r pin src got < "$TEST_TMP/AI.recover"
  assert_eq "an idle but running pane session is still the live one" "$mine" "$pin"
  assert_eq "and is recorded as the sole live one" "sole-live" "$src"
  assert_eq "and resolves its transcript" "$proj/$mine.jsonl" "$got"
}
