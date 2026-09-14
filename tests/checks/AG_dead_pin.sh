# Check AG -- a pin is believed for as long as its session is alive, and no
# longer.
#
# Check W covers a pin that names no transcript; check Y covers one that is
# ADOPTED on evidence of liveness. Neither covered what happens to that
# evidence afterwards, and nothing did: a pin was tested once, at adoption,
# and then held for the life of the pane whatever became of the session it
# named.
#
# That is how the 2026-09-14 misattribution lasted (see check AF for how it
# started). The pin was adopted at 16:14:33 from a session that had been
# alive for three seconds; that session wrote its last line seconds later and
# stopped; the panel was still reporting its model, its $0.30, its 9% context
# and its three turns at 16:48, thirty-four minutes after it had ended. The
# adoption test and the retention test are the same question -- is this
# session still being written to -- and only one of them was being asked.
#
# The second half is recovery. A panel that releases a pin and has nothing to
# replace it with is honest but useless, and the birth-time heuristic cannot
# help it: that only ever accepts a transcript born AFTER the panel started.
# The tty pins the hook writes are the evidence it can use instead -- after
# AF, every one of them is a session that was running in a real pane.
check_AG_dead_pin() {
  sandbox_new AG
  local proj handoff ttydir live dead turn
  proj="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  handoff="$HOME/.cache/claude-panel-pin/$(printf '%s' "$PWD" | tr '/' '-')"
  ttydir="$HOME/.cache/claude-panel-pin/tty"
  mkdir -p "$proj" "$HOME/.cache/claude-panel-pin" "$ttydir"
  turn='{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}'
  dead="$proj/dddddddd-1111-2222-3333-444444444444.jsonl"   # the review session
  live="$proj/11111111-1111-2222-3333-444444444444.jsonl"   # the pane's own
  printf '%s\n' "$turn" > "$dead"
  printf '%s\n' "$turn" > "$live"
  # Two transcripts, neither born after the panel, so no unpinned fallback
  # can fire and the pin is the only thing deciding anything.
  printf '%s\t%s\n' "dddddddd-1111-2222-3333-444444444444" "$(date +%s)" > "$handoff"

  local pin src got
  # ---- 1. adopted while live, released once it goes cold ----------------
  # Two ticks, because that is the shape of the incident: the pin was
  # correct-looking when it was taken and wrong afterwards.
  (
    load_panel 10 12
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE"
    touch -t 202601010000 "$dead"
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AG.cold"
  IFS='|' read -r pin src < <(head -1 "$TEST_TMP/AG.cold")
  assert_eq "a live session is adopted" "dddddddd-1111-2222-3333-444444444444" "$pin"
  assert_eq "from the directory file" "handoff" "$src"
  IFS='|' read -r pin src got < <(tail -1 "$TEST_TMP/AG.cold")
  assert_eq "and released once its transcript goes cold" "" "$pin"
  # The handoff file has not changed, so re-reading it is not new evidence.
  # Without the flap guard the very next line of the same tick takes the pin
  # straight back -- the aligned branch adopts unconditionally.
  assert_eq "and not re-adopted from the unchanged file that named it" "" "$got"

  # ---- 2. ...and replaced by the only live pane session in the repo -----
  # The recovery the pane never had. The tty pin is what the hook wrote for
  # the session in the split beside this panel.
  printf '%s\t%s\n' "11111111-1111-2222-3333-444444444444" "$(date +%s)" > "$ttydir/ttysA"
  (
    load_panel 10 12
    resolve_session
    touch -t 202601010000 "$dead"
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AG.recover"
  IFS='|' read -r pin src got < "$TEST_TMP/AG.recover"
  assert_eq "the live pane session is picked up" "11111111-1111-2222-3333-444444444444" "$pin"
  assert_eq "and is recorded as the sole live one" "sole-live" "$src"
  assert_eq "and resolves its transcript" "$live" "$got"

  # ---- 3. two live pane sessions in one repo is ambiguity, not an answer -
  # The rule this whole file is built on: an honest blank beats a confident
  # wrong one.
  local other
  other="$proj/22222222-1111-2222-3333-444444444444.jsonl"
  printf '%s\n' "$turn" > "$other"
  printf '%s\t%s\n' "22222222-1111-2222-3333-444444444444" "$(date +%s)" > "$ttydir/ttysB"
  (
    load_panel 10 12
    resolve_session
    touch -t 202601010000 "$dead"
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/AG.ambiguous"
  IFS='|' read -r pin got < "$TEST_TMP/AG.ambiguous"
  assert_eq "two live pane sessions resolve to neither" "" "$pin"
  assert_eq "and the pane stays honestly blind" "" "$got"
  rm -f "$ttydir/ttysB" "$other"

  # ---- 4. a PANE pin is not released for going quiet --------------------
  # Its key is the pane, so a quiet transcript there means the person at that
  # keyboard is reading rather than typing. There is nothing better to
  # replace it with and nothing to be gained by dropping it.
  local panedir
  panedir="$HOME/.cache/claude-panel-pin/pane"
  mkdir -p "$panedir"
  printf '%s\t%s\n' "11111111-1111-2222-3333-444444444444" "$(date +%s)" > "$ttydir/ttysA"
  # $$ is this shell, which is what the panel sees inside the subshell below
  # -- the pairing is refused if it names another process (check AA case 2).
  printf '%s\t%s\t%s\n' "ttysA" "$$" "$(date +%s)" > "$panedir/ttyTESTAG"
  (
    PANEL_PANE_TTY=ttyTESTAG load_panel 10 12
    resolve_session
    touch -t 202601010000 "$live"
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE"
  ) > "$TEST_TMP/AG.pane"
  IFS='|' read -r pin src < "$TEST_TMP/AG.pane"
  assert_eq "an idle pane keeps its own session" "11111111-1111-2222-3333-444444444444" "$pin"
  assert_eq "and keeps it as a pane pin" "pane" "$src"
  rm -f "$panedir/ttyTESTAG"

  # ---- 5. a directory pin names a repo; a tty pin names a pane ----------
  # The liveness window a stale handoff has to clear is half an hour, which
  # is right for "has this pane been read rather than typed in" and far too
  # generous to outrank a session being written to right now. A directory
  # pin that is not the one live pane session in the directory is the weaker
  # claim and stands aside.
  printf '%s\n' "$turn" > "$dead"
  touch "$live"
  printf '%s\t%s\n' "dddddddd-1111-2222-3333-444444444444" "$(( $(date +%s) - 7200 ))" > "$handoff"
  printf '%s\t%s\n' "11111111-1111-2222-3333-444444444444" "$(date +%s)" > "$ttydir/ttysA"
  (
    load_panel 10 12
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/AG.defer"
  IFS='|' read -r pin src got < "$TEST_TMP/AG.defer"
  assert_eq "the live pane session outranks a stale directory pin" \
    "11111111-1111-2222-3333-444444444444" "$pin"
  assert_eq "on the strength of naming a pane" "sole-live" "$src"
  assert_eq "and resolves that pane's transcript" "$live" "$got"

  # ---- 6. ...but only while it is the ONLY one ---------------------------
  # Give the directory pin's session a pane of its own and there are two
  # live pane sessions, which is no answer at all -- so the directory file,
  # which at least was written for this directory, keeps it.
  printf '%s\t%s\n' "dddddddd-1111-2222-3333-444444444444" "$(date +%s)" > "$ttydir/ttysC"
  (
    load_panel 10 12
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE"
  ) > "$TEST_TMP/AG.two"
  IFS='|' read -r pin src < "$TEST_TMP/AG.two"
  assert_eq "two live panes leave the directory pin standing" \
    "dddddddd-1111-2222-3333-444444444444" "$pin"
  assert_eq "and it is still the directory file answering" "handoff" "$src"
}
