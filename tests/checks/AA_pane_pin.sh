# Check AA -- the pin is addressed to a PANE, not to a directory.
#
# Check Y proves a handoff file gets the right session into the right panel.
# This one is about the key that file is stored under. It used to be the
# project directory, and that key is wrong the moment a repo has two Claude
# Code sessions open at once -- which is the ordinary way this machine is
# used. Every launch in a directory overwrote the one pin every panel in that
# directory read, so all of them followed whichever session started last.
#
# Both halves of that were observed on 2026-09-08/09 in wordpress-cyber-devtools:
#
#   * 21:55 -- a second session opened, and the panel whose pane was running
#     fcdc479e adopted 5f46b180 within a second. It spent the night showing
#     another pane's turns and cost as its own. Nothing on screen said so.
#   * 09:03 -- a third window opened and was never typed into, so Claude Code
#     wrote no transcript for it. All three panels adopted its id and showed
#     "no active Claude Code session found" against sessions that were live
#     in the splits beside them. A handoff pin is never timed out, so that
#     was permanent.
#
# The pane's identity is its claude's controlling terminal, paired to the
# panel's own by the launcher -- the only process that ever sees both.
check_AA_pane_pin() {
  sandbox_new AA
  local proj mine theirs dirpin pinsdir panedir
  proj="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$proj"
  dirpin="$HOME/.cache/claude-panel-pin/$(printf '%s' "$PWD" | tr '/' '-')"
  pinsdir="$HOME/.cache/claude-panel-pin/tty"
  panedir="$HOME/.cache/claude-panel-pin/pane"
  mkdir -p "$pinsdir" "$panedir"

  mine="$proj/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  theirs="$proj/cccccccc-1111-2222-3333-444444444444.jsonl"
  # Two live transcripts in one directory, neither born after the panel and
  # neither alone -- so no unpinned fallback can fire and the pin is the only
  # thing deciding which one this pane is.
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}' > "$mine"
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m2","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}' > "$theirs"

  # The pairing the launcher writes: this panel process (ttyTEST0) belongs to
  # the claude in ttyTEST1. $$ inside the subshells below is this same shell.
  printf '%s\t%s\t%s\n' "ttyTEST1" "$$" "$(date +%s)" > "$panedir/ttyTEST0"

  # ---- 1. the pane pin wins over the directory pin ----------------------
  # The directory pin names the OTHER session and was written seconds ago, so
  # under the old key it would be adopted as "fresh, written for this launch".
  printf '%s\t%s\n' "cccccccc-1111-2222-3333-444444444444" "$(date +%s)" > "$dirpin"
  printf '%s\t%s\n' "aaaaaaaa-1111-2222-3333-444444444444" "$(date +%s)" > "$pinsdir/ttyTEST1"
  (
    PANEL_PANE_TTY=ttyTEST0 load_panel 10 12
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AA.pane"
  local pin src got
  IFS='|' read -r pin src got < "$TEST_TMP/AA.pane"
  assert_eq "the pane's own pin is preferred to the directory's" "aaaaaaaa-1111-2222-3333-444444444444" "$pin"
  assert_eq "and is recorded as coming from the pane" "pane" "$src"
  assert_eq "and resolves this pane's transcript" "$mine" "$got"

  # ---- 2. a pairing written for a different process is refused ----------
  # Terminal names are recycled. Without the pid this panel would inherit the
  # pairing of whatever panel held ttyTEST0 before it and follow a claude it
  # has nothing to do with -- the same misattribution, one split later.
  printf '%s\t%s\t%s\n' "ttyTEST1" "999999" "$(date +%s)" > "$panedir/ttyTEST0"
  (
    PANEL_PANE_TTY=ttyTEST0 load_panel 10 12
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE"
  ) > "$TEST_TMP/AA.stalepair"
  IFS='|' read -r pin src < "$TEST_TMP/AA.stalepair"
  assert_eq "a pairing naming another process is not this panel's" "cccccccc-1111-2222-3333-444444444444" "$pin"
  assert_eq "so the directory-keyed fallback is what answers" "handoff" "$src"

  # ---- 3. an unpaired panel still gets the directory pin ----------------
  # Started by hand, or through a path with no launcher. The old key is the
  # fallback, not a thing removed.
  rm -f "$panedir/ttyTEST0"
  (
    PANEL_PANE_TTY=ttyTEST0 load_panel 10 12
    resolve_session
    printf '%s|%s\n' "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AA.unpaired"
  IFS='|' read -r src got < "$TEST_TMP/AA.unpaired"
  assert_eq "an unpaired panel falls back to the directory pin" "handoff" "$src"
  assert_eq "and resolves what that pin names" "$theirs" "$got"

  # ---- 4. the 09:03 failure, exactly -----------------------------------
  # A window opened in this directory long after this panel started and never
  # typed into: a directory pin naming a session with no transcript at all.
  # The old freshness test was one-sided -- "written 18 hours AFTER I started"
  # passed as "written for this launch" -- so the pin was adopted
  # unconditionally and, never being timed out, held forever. The panel must
  # keep the session it already had.
  printf '%s\t%s\n' "aaaaaaaa-1111-2222-3333-444444444444" "$(date +%s)" > "$dirpin"
  (
    PANEL_PANE_TTY=ttyTEST0 load_panel 10 12
    resolve_session
    # ...and now the empty window opens, well after this panel started.
    printf '%s\t%s\n' "dddddddd-1111-2222-3333-444444444444" "$(( PANEL_START_EPOCH + 64800 ))" > "$dirpin"
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/AA.emptywindow"
  IFS='|' read -r pin got < "$TEST_TMP/AA.emptywindow"
  assert_eq "a pin written long after launch, naming no transcript, is refused" "aaaaaaaa-1111-2222-3333-444444444444" "$pin"
  assert_eq "and the pane keeps the session it was already showing" "$mine" "$got"

  # ---- 5. the 21:55 failure ---------------------------------------------
  # Same shape, but the late pin names a session that IS live. That is a
  # second pane's session, and adopting it is how a panel spent a night
  # reporting another conversation's cost. It has to prove itself on the
  # stale path, and a live transcript used to be all that took: the pin was
  # adopted and the limit of the unpaired fallback was that it could not
  # tell the two apart.
  #
  # It can tell them apart here now, on evidence it already had. cccccccc is
  # live but nothing ever registered it as a PANE session -- no tty pin --
  # while aaaaaaaa has one and is live, so aaaaaaaa is the only live pane
  # session in this directory and the directory pin stands aside for it
  # (check AG case 5). After check AF a live transcript with no tty pin is
  # most likely a headless `--print` run, which is nobody's pane.
  #
  # The limit that remains is narrower: two siblings that BOTH registered a
  # pane are two candidates, which is no answer, and an unpaired panel is
  # back to the directory file (check AG case 6). Only the pairing settles
  # that one.
  (
    PANEL_PANE_TTY=ttyTEST0 load_panel 10 12
    resolve_session
    touch "$theirs"
    printf '%s\t%s\n' "cccccccc-1111-2222-3333-444444444444" "$(( PANEL_START_EPOCH + 64800 ))" > "$dirpin"
    resolve_session
    printf '%s\n' "$PIN_SESSION_ID"
  ) > "$TEST_TMP/AA.late_live"
  assert_eq "a live sibling that never registered a pane does not displace this one" \
    "aaaaaaaa-1111-2222-3333-444444444444" "$(cat "$TEST_TMP/AA.late_live")"
  # ...and when it does register one, the ambiguity is real and is not
  # resolved by guessing -- the directory pin answers, as before.
  printf '%s\t%s\n' "cccccccc-1111-2222-3333-444444444444" "$(date +%s)" > "$pinsdir/ttyTEST2"
  (
    PANEL_PANE_TTY=ttyTEST0 load_panel 10 12
    resolve_session
    touch "$theirs"
    printf '%s\t%s\n' "cccccccc-1111-2222-3333-444444444444" "$(( PANEL_START_EPOCH + 64800 ))" > "$dirpin"
    resolve_session
    printf '%s\n' "$PIN_SESSION_ID"
  ) > "$TEST_TMP/AA.late_live2"
  assert_eq "an unpaired panel still cannot tell two pane sessions apart" \
    "cccccccc-1111-2222-3333-444444444444" "$(cat "$TEST_TMP/AA.late_live2")"
  rm -f "$pinsdir/ttyTEST2"

  # ...but a PAIRED one can, which is the whole point.
  printf '%s\t%s\t%s\n' "ttyTEST1" "$$" "$(date +%s)" > "$panedir/ttyTEST0"
  (
    PANEL_PANE_TTY=ttyTEST0 load_panel 10 12
    resolve_session
    touch "$theirs"
    printf '%s\t%s\n' "cccccccc-1111-2222-3333-444444444444" "$(( PANEL_START_EPOCH + 64800 ))" > "$dirpin"
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/AA.paired_late"
  IFS='|' read -r pin got < "$TEST_TMP/AA.paired_late"
  assert_eq "a paired panel ignores a sibling session opening beside it" "aaaaaaaa-1111-2222-3333-444444444444" "$pin"
  assert_eq "and stays on its own transcript" "$mine" "$got"
}
