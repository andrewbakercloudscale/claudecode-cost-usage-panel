# Check I -- a model the panel cannot price or size is never answered silently.
#
# Two separate silent-wrong-number risks, one per column:
#
#   Cost.    An id absent from PRICES was priced at DEFAULT_PRICE ($3/$15)
#            with no indication. A Claude Fable 5.1 turn at its real $10/$50
#            was therefore under-reported 3.3x, and looked like every other
#            row. It is still priced at the default -- excluding it would
#            silently understate the session total, which is worse -- but the
#            table now names the id underneath.
#   Context. The window used to default to 1M for anything unrecognised. Every
#            model in PRICES is 1M except Haiku 4.5 (verified against the
#            claude-api model table, cached 2026-06-24), so an unknown id is
#            by definition a model released after that table, whose window is
#            not guessable. It now returns 0 and the panel renders N/A.
check_I_unknown_model() {
  sandbox_new I
  local tp="$HOME/.claude/projects/test-project/sess.jsonl"

  # Known model first, as the control: without it, every assertion below
  # would also pass on a panel that simply rendered nothing.
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":1000,"cache_creation_input_tokens":200}}}' > "$tp"
  load_panel 10 12 ""
  latest="$tp"
  session_stats_refresh
  assert_eq "a known model has a window" "1000000" "$SESS_WIN"
  assert_not_contains "and no unpriced footnote" "no known price" "$SESS_TABLE"

  # Claude Fable 5.1 -- present in the price table, so it must behave like
  # any other known model rather than like the unknown case below.
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m2","model":"claude-fable-5-1","usage":{"input_tokens":1000000,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' > "$tp"
  session_stats_refresh
  assert_eq "Fable 5.1 is priced at its own rate, not the default" "10.000000" "$SESS_COST"
  assert_eq "and has a window" "1000000" "$SESS_WIN"

  # An id from after the table was written.
  printf '%s\n' '{"type":"assistant","timestamp":"2026-09-01T10:00:00.000Z","message":{"id":"m3","model":"claude-nonesuch-9","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' > "$tp"
  session_stats_refresh
  assert_eq "an unknown model reports no window" "0" "$SESS_WIN"
  assert_contains "and names itself as unpriced" "claude-nonesuch-9" "$SESS_TABLE"
  assert_contains "under an explicit caveat" "no known price" "$SESS_TABLE"
  assert_eq "and no session cost is invented for it" "" "$SESS_COST"

  # The rendered line must say N/A, not 0%.
  #
  # Driven the way the render loop drives it, because build_summary reads
  # globals that resolve_session and the frame setup publish -- `sess_id`
  # and `cols` among them -- and this check used to call it bare with
  # `2>/dev/null`. Under `set -u` that produced "sess_id: unbound variable",
  # a one-line stump on stdout, and a failure that read as "the panel prints
  # a percentage against an unknown window" when the truth was that no
  # summary had been built at all. It is the exact trap panel_tick_slow's
  # comment describes, and it sat failing for long enough to be treated as
  # background noise -- which is the real cost of a check that fails for a
  # reason other than the one it names.
  #
  # resolve_session only looks in the transcript directory Claude Code would
  # use for THIS cwd (its path is $PWD with every character outside
  # [A-Za-z0-9] replaced by "-" -- see check AE), so the
  # transcript is placed there and found by the panel's own resolution
  # rather than assigned to $latest by hand -- same reasoning as check V.
  local proj_dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$proj_dir"
  cp "$tp" "$proj_dir/sess-i.jsonl"
  load_panel 10 12 "sess-i"
  cols=100; rows=40; export COLS=100
  seed_recent
  panel_tick_slow
  session_stats_refresh
  assert_eq "the panel's own resolution finds the unknown-model transcript" \
    "$proj_dir/sess-i.jsonl" "$latest"
  assert_eq "and still reports no window for it" "0" "$SESS_WIN"

  # stderr is asserted, not discarded. A builder that dies half way still
  # prints its first line, so any assertion about what the summary CONTAINS
  # can only be trusted once the summary is known to have been built at all.
  local summary err
  err="$TEST_TMP/I-build-summary.err"
  summary=$(build_summary 2>"$err")
  assert_eq "the summary builds with no stderr at all" "" "$(cat "$err")"
  assert_contains "the summary shows N/A for context" "Context Usage: N/A" "$summary"
  assert_not_contains "and never a percentage against an unknown window" "(0%)" "$summary"
}
