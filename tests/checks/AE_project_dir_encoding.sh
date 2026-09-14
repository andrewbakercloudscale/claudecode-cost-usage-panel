# Check AE -- the panel finds its own transcript directory for a project path
# that is not made purely of letters, digits and slashes.
#
# Claude Code names a project's transcript directory by replacing EVERY
# character outside [A-Za-z0-9] in the cwd with a "-". The panel used to
# apply `tr '/' '-'`, which agrees for most paths and disagrees for any path
# containing a space, a dot, or an underscore.
#
# The disagreement is invisible in the way that matters here. A wrong
# directory name is not an error: it is a directory with no transcripts in
# it, which is indistinguishable from a project that has never been used. So
# $latest stayed empty for the whole life of the pane and the panel rendered
# its honest "nothing here" state forever -- "(no active Claude Code session
# found)", "Model: Unknown", "Context Usage: N/A" -- while Today, the block,
# Recent and Top Sessions, which glob the corpus and never build this key,
# kept updating beside them. Some sections permanently frozen, the rest live.
#
# Two assertions, deliberately, because either alone can pass on a broken
# panel:
#   * the encoder against the real rule -- but an encoder is only a string
#     function, and the old one was also "correct" for every path anyone
#     happened to test it on;
#   * resolve_session() driven from a real $PWD containing a space, which is
#     what actually broke. That one cannot pass unless the panel opens the
#     directory Claude Code really wrote to.
#
# Against the pre-change panel the first fails as a wrong string and the
# second as an empty $latest.
check_AE_project_dir_encoding() {
  sandbox_new AE

  # The rule, stated independently of the panel rather than by calling the
  # panel's own function twice. These are the two shapes observed on the
  # machine where this was found: a folder named with spaces, and a folder
  # named after a domain.
  load_panel 10 12 ""
  assert_eq "spaces in a folder name become dashes" \
    "-Users-me-github-iphone-Image-Manager" \
    "$(project_key '/Users/me/github/iphone Image Manager')"
  assert_eq "dots in a folder name become dashes" \
    "-Users-me-websites-easyenglishlessons-com" \
    "$(project_key '/Users/me/websites/easyenglishlessons.com')"
  # No collapsing of runs: `/a/-b` is two separate substitutions, not one.
  # Asserted because a plausible "tidier" implementation (tr -s, or a sed
  # that squeezes) would silently stop matching Claude Code for exactly the
  # scratchpad-style paths that contain adjacent separators.
  assert_eq "adjacent separators are not collapsed" \
    "-tmp-claude-501--Users-me" \
    "$(project_key '/tmp/claude-501/-Users-me')"
  # And the path shape the old rule got right, so the fix is not a swap of
  # one wrong answer for another.
  assert_eq "an all-alphanumeric path is unchanged by the fix" \
    "-Users-me-github-panel" \
    "$(project_key '/Users/me/github/panel')"

  # ---- and now the thing that actually broke ----
  # A real working directory with a space in it, and a transcript filed
  # where Claude Code would file it. Nothing below names the encoded
  # directory by hand; the panel has to derive it.
  local origin="$PWD"
  local work="$SBX/home/proj dir"
  mkdir -p "$work"
  cd "$work" || { _fail "could not enter the test working directory" "$work" "$PWD"; return 1; }

  local proj_dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$proj_dir"
  local f="$proj_dir/sess-ae.jsonl"
  local today; today=$(date +%Y-%m-%d)
  printf '%s\n' \
    "{\"type\":\"user\",\"cwd\":\"$work\",\"timestamp\":\"${today}T10:00:00.000Z\"}" \
    "{\"type\":\"assistant\",\"message\":{\"model\":\"claude-opus-5\",\"id\":\"m1\",\"usage\":{\"input_tokens\":10,\"output_tokens\":10}},\"cwd\":\"$work\",\"timestamp\":\"${today}T10:01:00.000Z\"}" \
    > "$f"

  printf '{"daily":[]}\n' > "$CCUSAGE_FIXTURE_DIR/daily.json"
  printf '{"sessions":[{"period":"sess-ae","totalCost":26.00}]}\n' > "$CCUSAGE_FIXTURE_DIR/session.json"
  printf '{"blocks":[]}\n' > "$CCUSAGE_FIXTURE_DIR/blocks.json"
  printf '{}' > "$HOME/.cache/claude-hourly-buckets.json"

  # Reloaded inside the new $PWD: the panel resolves its project directory
  # on every tick, but the pin-file path is computed once at load.
  load_panel 10 12 ""
  cols=100; rows=40; export COLS=100
  seed_recent
  panel_tick_slow
  session_stats_refresh

  assert_eq "the panel looks in the directory Claude Code actually wrote to" \
    "$proj_dir" "${project_dir:-}"
  assert_eq "and resolves the session living in it" "$f" "${latest:-}"
  assert_eq "so the model is known, not Unknown" "Opus 5" "${model_label:-}"

  local frame plain
  frame=$(build_summary 2>/dev/null)
  # Stripped, because the model is printed wrapped in its tier colour and the
  # raw frame therefore contains neither "Model: Unknown" nor "Model: Opus 5"
  # -- an assertion either way round would pass on both panels. See
  # strip_ansi in the harness.
  plain=$(strip_ansi "$frame")
  assert_contains "the header names the resolved model" "Model: Opus 5" "$plain"
  assert_not_contains "and no longer says Unknown" "Model: Unknown" "$plain"
  # This one carries no colour boundary inside it, so it is safe either way
  # -- and it is one of the two lines the frozen pane actually showed.
  assert_not_contains "and does not report the context as unknowable" \
    "Context Usage: N/A" "$plain"
  # The third casualty of the same key: `ls "$project_dir"/*.jsonl` supplies
  # the session ids that the folder's spend is summed over, so a directory
  # that does not exist printed $0.00 against a session that had spent $26.
  assert_contains "and the folder's spend is its sessions', not \$0" \
    "Folder: proj dir (\$26)" "$frame"

  local table; table=$(build_session_table 2>/dev/null)
  assert_not_contains "and This Session is not permanently empty" \
    "no active Claude Code session found" "$table"

  cd "$origin" || true
}
