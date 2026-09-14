# Check AH -- context bloat colours the WHOLE row, not one cell.
#
# The panel spent a session at 95%+ of a 1M window drawing five-column rows in
# which exactly one cell -- the Input total -- was tinted purple, and the four
# columns around it stayed the ordinary colour. That is what "nothing is
# wrong" looks like from a metre away, and it was duly scanned past turn after
# turn. The rule now: from CTX_RED up, the context band colours the entire row
# and the entire "Context Usage" line, label included.
#
# Both halves of that are asserted here, and so is the half that must NOT
# happen: yellow (40%) is routine and still tints only the one cell. Without
# the yellow case this check would pass just as happily against a panel that
# painted every row in every session, which is the noise the old delta-only
# rule was guarding against and is not what replaced it.
check_AH_ctx_row_color() {
  local origin="$PWD"

  # Renders one frame at a chosen context occupancy. Deltas are held at 200
  # tokens -- far below MIN_DELTA_ALERT -- so delta_color() is green in every
  # case below and the context band is provably the only thing colouring
  # anything. Sets AH_CTX_LINE and AH_ROWS.
  _ah_render() { # $1 = cache-read tokens for the first turn
    sandbox_new AH
    local work="$SBX/home/proj"
    mkdir -p "$work"
    cd "$work" || { _fail "could not enter the test working directory" "$work" "$PWD"; return 1; }
    local proj_dir="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr -c 'a-zA-Z0-9' '-')"
    mkdir -p "$proj_dir"
    local f="$proj_dir/sess-ah.jsonl" today i
    today=$(date +%Y-%m-%d)
    {
      printf '{"type":"user","cwd":"%s","timestamp":"%sT10:00:00.000Z"}\n' "$work" "$today"
      for i in 1 2 3; do
        printf '{"type":"assistant","cwd":"%s","timestamp":"%sT10:0%s:00.000Z","message":{"id":"m%s","model":"claude-opus-5","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":%s,"cache_creation_input_tokens":200}}}\n' \
          "$work" "$today" "$i" "$i" "$(( $1 + i * 1000 ))"
      done
    } > "$f"
    printf '{}' > "$HOME/.cache/claude-hourly-buckets.json"
    load_panel 10 12 ""
    cols=100; rows=40; export COLS=100
    seed_recent
    panel_tick_slow
    session_stats_refresh
    AH_CTX_LINE=$(build_summary 2>/dev/null | grep -a 'Context Usage' || true)
    AH_ROWS=$(printf '%s\n' "$SESS_TABLE" | grep -a 'Opus 5' || true)
  }

  # A row is "whole" when its colour opens before the turn number and the
  # first reset in the line is the one that closes it -- i.e. nothing inside
  # the row switches colour back. Printed as a boolean so a failure names the
  # line it actually saw.
  _ah_whole_row() { # $1 = row, $2 = expected opening escape (e.g. '[35m')
    case "$1" in
      "  $(printf '\033')$2"*) ;;
      *) printf 'no'; return ;;
    esac
    local body="${1#"  $(printf '\033')$2"}"
    case "${body%"$(printf '\033')[0m"}" in
      *"$(printf '\033')["*) printf 'no' ;;
      *) printf 'yes' ;;
    esac
  }

  # ---- 95% of a 1M window: purple, everywhere -----------------------------
  _ah_render 950000
  assert_contains "the context line reports the band it is in" "(95%)" \
    "$(strip_ansi "$AH_CTX_LINE")"
  # The label, not just the figure. A magenta open must precede the emoji and
  # the words -- this is the specific thing that was invisible.
  case "$AH_CTX_LINE" in
    "  $(printf '\033')[35m"*"Context Usage:"*) assert_eq "the whole Context Usage line goes purple" "1" "1" ;;
    *) assert_eq "the whole Context Usage line goes purple" "1" "0" ;;
  esac
  local row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    assert_eq "a 95% turn row is purple end to end" "yes" "$(_ah_whole_row "$row" '[35m')"
  done <<< "$AH_ROWS"

  # ---- 65%: red, same rule ------------------------------------------------
  _ah_render 645000
  case "$AH_CTX_LINE" in
    "  $(printf '\033')[31m"*"Context Usage:"*) assert_eq "the whole Context Usage line goes red" "1" "1" ;;
    *) assert_eq "the whole Context Usage line goes red" "1" "0" ;;
  esac
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    assert_eq "a 65% turn row is red end to end" "yes" "$(_ah_whole_row "$row" '[31m')"
  done <<< "$AH_ROWS"

  # ---- 45%: yellow stays a single cell ------------------------------------
  # The counter-case. 40% of a window is an ordinary working session, and a
  # panel that shouts here has stopped distinguishing anything.
  _ah_render 445000
  case "$AH_CTX_LINE" in
    "  $(printf '\033')["*) assert_eq "a yellow context line leaves its label plain" "1" "0" ;;
    *) assert_eq "a yellow context line leaves its label plain" "1" "1" ;;
  esac
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    assert_eq "a 45% turn row is not painted whole" "no" "$(_ah_whole_row "$row" '[33m')"
    assert_contains "but its Input total still carries the yellow tint" \
      "$(printf '\033')[33m" "$row"
  done <<< "$AH_ROWS"

  cd "$origin" || true
  unset -f _ah_render _ah_whole_row
}
