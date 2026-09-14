# Check W -- a pin that names no transcript must not cost the whole session.
#
# The pin reaches the panel as synthetic keystrokes typed into a brand-new
# split. That is not a lossless channel: a dropped character, or one of the
# user's own keystrokes landing in the same pane, rewrites the id in place.
# An observed pane ran with
#     9e435181h-888e-4f0c-811-3befb80226t3d
# against a real session id of
#     9e435181-888e-4f0c-81f1-3befb802263d
# -- an 'h' and a 't' woven in from the real keyboard, an 'f' lost.
#
# The panel pinned to that, found no such file, and set latest="" on every
# tick for the rest of the pane's life. `Model: Unknown`, `Session $-0.00`,
# `Context Usage: N/A`, "no active Claude Code session found" -- hours into a
# busy session, with every account-wide figure beside it correct, which is
# exactly the shape that reads as "the panel is broken" rather than "the pin
# is wrong".
#
# So: a pin is a hint, not a contract. It wins while it resolves; it is
# discarded when it demonstrably cannot.
check_W_pin_recovery() {
  sandbox_new W
  local proj tp
  proj="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$proj"
  tp="$proj/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl"

  # ---- 1. a pin that is not a UUID is corrupt on its face ----------------
  # There is nothing to wait for: Claude Code cannot ever write that file.
  # Drop it at startup and detect the session the unpinned way instead.
  (
    load_panel 10 12 "9e435181h-888e-4f0c-811-3befb80226t3d"
    # Written AFTER the panel started, so it is a session that began
    # alongside this pane -- what the birth-time heuristic looks for.
    printf '%s\n' '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":1,"output_tokens":1}}}' > "$tp"
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/W.malformed"
  local pin_after latest_after
  IFS='|' read -r pin_after latest_after < "$TEST_TMP/W.malformed"
  assert_eq "a malformed pin is discarded, not carried" "" "$pin_after"
  assert_eq "and the session is found anyway" "$tp" "$latest_after"

  # ---- 2. a well-formed pin still gets its grace period ------------------
  # A pin whose transcript has not landed yet is the ordinary case for the
  # first seconds of every session. It must NOT be thrown away on tick one,
  # or the pin would never do its job (telling two concurrent sessions in
  # one directory apart) at all.
  (
    load_panel 10 12 "11111111-2222-3333-4444-555555555555"
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/W.grace"
  IFS='|' read -r pin_after latest_after < "$TEST_TMP/W.grace"
  assert_eq "a pin that has not landed yet is kept" "11111111-2222-3333-4444-555555555555" "$pin_after"
  assert_eq "and nothing is claimed in the meantime" "" "$latest_after"

  # ---- 3. ...but not forever --------------------------------------------
  # Past the grace period the pin is not slow, it is wrong. A corruption
  # that happens to stay UUID-shaped is indistinguishable from one that
  # does not, so this is the case that actually rescues the pane.
  (
    load_panel 10 12 "11111111-2222-3333-4444-555555555555"
    PANEL_START_EPOCH=$(( PANEL_START_EPOCH - 1000 ))
    resolve_session
    printf '%s|%s\n' "$PIN_SESSION_ID" "$latest"
  ) > "$TEST_TMP/W.expired"
  IFS='|' read -r pin_after latest_after < "$TEST_TMP/W.expired"
  assert_eq "a pin that never resolves is abandoned" "" "$pin_after"
  assert_eq "and the pane recovers the real session" "$tp" "$latest_after"

  # ---- 4. a pin that DOES resolve still wins ----------------------------
  # The whole point of the pin is to beat the heuristic when both have an
  # answer. Two transcripts here, both born after this panel: without the
  # pin the newest wins, and that is the wrong pane's session.
  local pinned other
  pinned="$proj/99999999-8888-7777-6666-555555555555.jsonl"
  (
    load_panel 10 12 "99999999-8888-7777-6666-555555555555"
    printf '{}\n' > "$pinned"
    sleep 1
    other="$proj/12121212-3434-5656-7878-909090909090.jsonl"
    printf '{}\n' > "$other"
    resolve_session
    printf '%s\n' "$latest"
  ) > "$TEST_TMP/W.wins"
  assert_eq "a resolvable pin beats the newest-file guess" "$pinned" "$(cat "$TEST_TMP/W.wins")"
}

