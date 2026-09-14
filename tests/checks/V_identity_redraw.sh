# Check V -- the header redraws when the session identity changes, instead of
# waiting out the slow tier.
#
# Session identity is resolved on every FAST tick but rendered by the header,
# which is slow tier. So a model learned at 10s did not reach the screen for
# up to SLOW_REFRESH (120s).
#
# Every new pane starts in exactly that state: the transcript exists but has
# no ASSISTANT line yet, so the scan correctly reports "unknown", the first
# frame renders `Model: Unknown`, and it stays there for two minutes while
# the fast-tier turn table below it already names the model on every row.
# One frame contradicting itself, on every session start.
#
# What is asserted is slow_frame_due(), the loop's actual decision, because
# the first version of this check asserted build_summary's OUTPUT and passed
# against the unfixed panel -- build_summary always renders the current
# identity; the bug was that the loop did not call it. The only assertion
# that failed was a grep of the panel source for a variable name, which says
# nothing about what the loop does with it. Hence the seam.
#
# The clock is pinned via last_slow, so nothing here can pass by SLOW_REFRESH
# genuinely elapsing.
#
# Against the pre-change panel this fails as `slow_frame_due: command not
# found` rather than as a wrong boolean, and that is the honest signal
# available: the decision was three lines inline in the render loop, so there
# was nothing to call. Read a 127 here as "the seam is gone", not as a
# passing assertion.
check_V_identity_redraw() {
  sandbox_new V
  # resolve_session derives its project directory from $PWD (Claude Code
  # encodes a project's transcript dir as its cwd with every character
  # outside [A-Za-z0-9] replaced by "-" -- see check AE), so build the
  # directory the panel will ACTUALLY look in rather than assigning $latest
  # by hand. That keeps the pinned-session path itself under test instead of
  # stubbed around.
  local proj_dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$proj_dir"
  local sid="sess-v" f="$proj_dir/sess-v.jsonl"
  local today; today=$(date +%Y-%m-%d)

  # A transcript in the state a pane launches in: a user line, a cwd, a
  # timestamp -- and no assistant line, so the model is genuinely not
  # knowable yet.
  printf '%s\n' \
    "{\"type\":\"user\",\"cwd\":\"$HOME/proj\",\"timestamp\":\"${today}T10:00:00.000Z\"}" > "$f"

  printf '{"daily":[]}\n' > "$CCUSAGE_FIXTURE_DIR/daily.json"
  printf '{"sessions":[]}\n' > "$CCUSAGE_FIXTURE_DIR/session.json"
  printf '{"blocks":[]}' > "$CCUSAGE_FIXTURE_DIR/blocks.json"
  printf '{}' > "$HOME/.cache/claude-hourly-buckets.json"
  load_panel 10 12 "$sid"
  cols=100; rows=40; export COLS=100
  seed_recent

  # The state left behind by a frame that has just been rendered: the clock
  # is not due, the pane has not been resized. Only an identity change can
  # make the next tick due.
  resolve_session
  local now; now=$(panel_now)
  last_slow=$now
  last_cols=$cols
  last_model_label="${model_label:-}"

  assert_eq "a pane with no assistant line yet resolves as Unknown" \
    "Unknown" "${model_label:-}"
  slow_frame_due "$now"
  assert_eq "and with nothing changed, no frame is due" "1" "$?"

  # The first assistant turn lands. This is the moment the model becomes
  # knowable; the clock does not move and the pane is not resized.
  printf '%s\n' \
    "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-opus-5\"},\"cwd\":\"$HOME/proj\",\"timestamp\":\"${today}T10:01:00.000Z\"}" >> "$f"

  resolve_session
  assert_eq "the next fast tick resolves the real model" "Opus 5" "${model_label:-}"
  slow_frame_due "$now"
  assert_eq "which makes the frame due immediately, on the same clock" "0" "$?"

  # And the frame the loop would then render says so.
  local frame; frame=$(build_summary 2>/dev/null)
  assert_contains "the redrawn header names the model" "Opus 5" "$frame"
  # Through strip_ansi, because the frame this used to be asserted against
  # raw: the model is printed wrapped in its tier colour, so the literal
  # "Model: Unknown" never appeared in any frame and the assertion could not
  # fail on any panel. See strip_ansi in the harness.
  assert_not_contains "and no longer says Unknown" \
    "Model: Unknown" "$(strip_ansi "$frame")"

  # Once rendered, the identity is no longer a reason to redraw -- otherwise
  # every tick would be a slow tick for the rest of the session, quietly
  # undoing the whole slow tier.
  last_model_label="${model_label:-}"
  slow_frame_due "$now"
  assert_eq "and having shown it, the frame is not due again" "1" "$?"
}
