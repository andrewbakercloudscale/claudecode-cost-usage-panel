# Check Y -- the pin arrives through the filesystem, and survives a restart.
#
# Check W is about a pin that is WRONG. This one is about the two ways the
# panel used to end up with no pin at all:
#
#   * The id was typed into the new split as synthetic keystrokes, so the
#     user's own typing could rewrite it (W case 1). It now travels in a file
#     that ~/.local/bin/claude-panel-launch.sh and the Claude Code
#     SessionStart hook both write, and nothing types.
#   * A panel restarted into a conversation already in progress could never
#     recover: the unpinned heuristic only accepts a transcript BORN AFTER
#     the panel started, and the single-transcript fallback needs the
#     directory to hold exactly one file. A real project directory holds a
#     dozen. That pane read "no active Claude Code session found" for five
#     hours while the session was live in the split beside it.
#
# The handoff file answers both, but it has to distinguish "written for this
# launch" from "left over from the last one" -- see adopt_handoff_pin.
check_Y_pin_handoff() {
  sandbox_new Y
  local proj live old handoff
  proj="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$proj" "$HOME/.cache/claude-panel-pin"
  handoff="$HOME/.cache/claude-panel-pin/$(printf '%s' "$PWD" | tr '/' '-')"
  live="$proj/aaaaaaaa-1111-2222-3333-444444444444.jsonl"
  old="$proj/bbbbbbbb-1111-2222-3333-444444444444.jsonl"
  # Two transcripts, both older than the panel, so NEITHER unpinned fallback
  # can fire: nothing was born after the panel started, and the directory
  # does not hold exactly one file. Without a handoff this pane is blind --
  # which is the bug, and is asserted as such first.
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}' > "$live"
  printf '{}\n' > "$old"

  # ---- 1. no handoff, nothing born after launch: honestly blind ----------
  (
    load_panel 10 12
    PANEL_START_EPOCH=$(( PANEL_START_EPOCH + 600 ))
    resolve_session
    printf '%s\n' "$latest"
  ) > "$TEST_TMP/Y.blind"
  assert_eq "with no handoff a restarted panel claims nothing" "" "$(cat "$TEST_TMP/Y.blind")"

  # ---- 2. a handoff written for THIS launch is simply the answer ---------
  printf '%s\t%s\n' "aaaaaaaa-1111-2222-3333-444444444444" "$(date +%s)" > "$handoff"
  (
    load_panel 10 12
    resolve_session
    printf '%s|%s|%s\n' "$PIN_SESSION_ID" "$PIN_SOURCE" "$latest"
  ) > "$TEST_TMP/Y.fresh"
  local pin src got
  IFS='|' read -r pin src got < "$TEST_TMP/Y.fresh"
  assert_eq "a fresh handoff is adopted" "aaaaaaaa-1111-2222-3333-444444444444" "$pin"
  assert_eq "and is recorded as coming from the file" "handoff" "$src"
  assert_eq "and resolves the transcript it names" "$live" "$got"

  # ---- 3. a stale handoff still counts while its session is being written -
  # This is the restart case: the file is hours old because the session it
  # names started hours ago -- and is still going, in the split beside us.
  printf '%s\t%s\n' "aaaaaaaa-1111-2222-3333-444444444444" "$(( $(date +%s) - 7200 ))" > "$handoff"
  touch "$live"
  (
    load_panel 10 12
    resolve_session
    printf '%s\n' "$latest"
  ) > "$TEST_TMP/Y.stale_live"
  assert_eq "a stale handoff whose session is live rescues a restarted panel" "$live" "$(cat "$TEST_TMP/Y.stale_live")"

  # ---- 4. ...but a stale handoff to a DEAD session is not evidence -------
  # Otherwise every new pane in a directory would open the last session that
  # ever ran there, which is the confidently-wrong answer this whole
  # function exists to avoid.
  touch -t 202601010000 "$live"
  (
    load_panel 10 12
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/Y.stale_dead"
  IFS='|' read -r pin got < "$TEST_TMP/Y.stale_dead"
  assert_eq "a stale handoff to a cold transcript is ignored" "" "$pin"
  assert_eq "and the pane stays honestly blind" "" "$got"

  # ---- 5. the observed failure, end to end ------------------------------
  # A corrupted argv pin AND a correct handoff: the pane that spent five
  # hours on "Model: Unknown" now resolves on its first tick.
  touch "$live"
  printf '%s\t%s\n' "aaaaaaaa-1111-2222-3333-444444444444" "$(date +%s)" > "$handoff"
  (
    load_panel 10 12 "9e435181h-888e-4f0c-811-3befb80226t3d"
    resolve_session
    printf '%s\n' "$latest"
  ) > "$TEST_TMP/Y.rescue"
  assert_eq "a corrupted typed pin is rescued by the handoff file" "$live" "$(cat "$TEST_TMP/Y.rescue")"
}
