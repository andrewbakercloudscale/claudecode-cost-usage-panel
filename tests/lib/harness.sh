# Shared test harness for ccusage-panel.sh.
#
# Two rules, both learned the expensive way in the sibling WordPress repo and
# restated here because this suite exists to guard silent failures:
#
#   1. Gate on exit codes, never on the absence of matched output. A check
#      that greps for a pattern and finds nothing has not passed; it has
#      failed to look.
#   2. Every check states how many assertions it ran, and the runner FAILS a
#      check that ran zero. A gate that has stopped covering anything must be
#      visible rather than reassuring -- silently covering nothing is worse
#      than no gate at all, because it stops you looking.

ASSERTIONS=0

_pass() { ASSERTIONS=$(( ASSERTIONS + 1 )); }
_fail() {
  ASSERTIONS=$(( ASSERTIONS + 1 ))
  printf '    FAIL: %s\n' "$1" >&2
  printf '      expected: %s\n' "$2" >&2
  printf '      actual:   %s\n' "$3" >&2
  FAILED=1
}

# Drop SGR escapes so a check can assert on a frame's TEXT.
#
# Rule 1 of this file, in its subtlest form. Almost every label in the panel
# is printed with its VALUE wrapped in a colour -- `Model: <esc>[33mUnknown`,
# `Session: <esc>[32m$4.10` -- so the literal string "Model: Unknown" does
# not occur in any frame the panel can emit, resolved or not. An
# assert_not_contains for it therefore passes on every panel ever built,
# including a totally broken one, while reading as though it caught
# something. Check V shipped exactly that assertion and it never once could
# have failed.
#
# So: assert on stripped text, or assert on a substring that carries no
# colour boundary inside it. Never on the absence of a label+value pair.
strip_ansi() { printf '%s' "$1" | LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g"; }

assert_eq() { # $1 label, $2 expected, $3 actual
  if [ "$2" = "$3" ]; then _pass; else _fail "$1" "$2" "$3"; fi
}
assert_ne() {
  if [ "$2" != "$3" ]; then _pass; else _fail "$1" "not $2" "$3"; fi
}
assert_contains() { # $1 label, $2 needle, $3 haystack
  case "$3" in *"$2"*) _pass ;; *) _fail "$1" "contains '$2'" "$3" ;; esac
}
assert_not_contains() {
  case "$3" in *"$2"*) _fail "$1" "does NOT contain '$2'" "$3" ;; *) _pass ;; esac
}

# Drive one slow tick in the same order the render loop does.
#
# The panel runs under `set -u` and its sections share globals that
# resolve_session() sets, so a check that calls build_summary() on its own
# gets a one-line stump and an "unbound variable" on stderr it never sees.
# That stump silently satisfies any assert_not_contains, which is how a
# check ends up proving nothing while reporting ok. Drive the real order.
panel_tick_slow() {
  # The frame geometry the render loop publishes before it calls either
  # builder. Defaulted rather than assigned, so a check that has set its own
  # width (V, S) keeps it. Without this, build_summary aborts on "cols:
  # unbound variable" after printing its first line -- and a check that then
  # asserts on what the summary CONTAINS fails naming the content, not the
  # crash, which is how check I spent months failing for the wrong reason.
  : "${cols:=100}"; : "${rows:=40}"; export COLS="$cols"
  resolve_session
  refresh_active_block
  block_clock_tick
}

# Backdate a file so a TTL lapses without the test sleeping for it.
#
# Relative to PANEL_FAKE_NOW when the clock is pinned, and this matters more
# than it looks: ccusage_cached() compares panel_now() against the cache
# file's REAL mtime, so a check that pins the clock to another date and then
# backdates against the real one produces an age of several million negative
# seconds. Every TTL then reads as fresh, the cache is served forever, and
# the check quietly measures nothing at all.
age_file() { # $1 path, $2 seconds
  local base ts
  if [ -n "${PANEL_FAKE_NOW:-}" ]; then
    ts=$(date -r "$(( PANEL_FAKE_NOW - $2 ))" +%Y%m%d%H%M.%S)
  else
    ts=$(date -v-"$2"S +%Y%m%d%H%M.%S)
  fi
  touch -t "$ts" "$1"
}

# Money comparisons, normalised. jq 1.7 preserves a number's original
# literal, so a fixture written as 10.00 comes back as "10.00" and a string
# compare against "10" fails on formatting rather than on value.
num() { awk -v v="$1" 'BEGIN{ printf "%.2f", v + 0 }'; }

# Backdate the WHOLE corpus tree, directories included.
#
# corpus_changed_since() is `find <projects> -newer <cache>` with no -type
# filter, deliberately: adding or removing a transcript bumps its parent
# DIRECTORY's mtime and no file's, so a files-only gate would miss new and
# archived sessions entirely. Which means a test that backdates only the
# files leaves the directories sitting at "now", the gate fires on those,
# and the test quietly asserts the opposite of what it reads as asserting.
age_corpus() { # $1 seconds
  local t; t=$(date -v-"$1"S +%Y%m%d%H%M.%S)
  find "$HOME/.claude/projects" -exec touch -t "$t" {} +
}

# ---- sandbox -------------------------------------------------------------
# Every check gets its own $HOME, so the panel's ~/.claude/projects corpus and
# ~/.cache caches are fixtures rather than the developer's real ones. $HOME is
# the only seam needed for that -- the panel reads both paths off it -- but it
# is load-bearing, so it is asserted here rather than assumed.
sandbox_new() { # $1 = name
  SBX="$TEST_TMP/$1"
  rm -rf "$SBX"
  mkdir -p "$SBX/home/.claude/projects/test-project" "$SBX/home/.cache" "$SBX/fixtures"
  export HOME="$SBX/home"
  export CCUSAGE_FIXTURE_DIR="$SBX/fixtures"
  export CCUSAGE_CALL_LOG="$SBX/ccusage-calls.log"
  : > "$CCUSAGE_CALL_LOG"
  # A corpus with at least one file, so corpus_changed_since() has something
  # to compare against. Its mtime is the thing tests move.
  #
  # Backdated an hour on creation, because "the corpus has not changed since
  # this cache entry" is only expressible if the corpus can be OLDER than the
  # entry. A freshly written seed file is newer than every cache file a test
  # can then age, so the gate would correctly refetch every time and the
  # test would be asserting nothing it thought it was.
  printf '{}\n' > "$HOME/.claude/projects/test-project/seed.jsonl"
  age_corpus 3600

  # Empty-but-valid defaults for every query the panel makes. A check
  # overrides only the ones it is about; without these a missing fixture
  # makes the stub exit 70, and an empty report is indistinguishable from a
  # deliberate one.
  printf '{"daily":[]}\n'   > "$CCUSAGE_FIXTURE_DIR/daily.json"
  printf '{"weekly":[]}\n'  > "$CCUSAGE_FIXTURE_DIR/weekly.json"
  printf '{"monthly":[]}\n' > "$CCUSAGE_FIXTURE_DIR/monthly.json"
  printf '{"sessions":[]}\n' > "$CCUSAGE_FIXTURE_DIR/session.json"
  printf '{"blocks":[]}\n'  > "$CCUSAGE_FIXTURE_DIR/blocks.json"

  # The panel and the cost-alert hook both SOURCE claude-day-projection.sh
  # and both refuse to run without it -- deliberately, because a panel that
  # silently lost its projection would draw today's actual spend as the
  # end-of-day forecast, a plausible-looking number and so the worst kind of
  # wrong. A sandbox that omits it is not modelling an installed machine, so
  # it is linked in rather than the requirement being softened to suit the
  # tests.
  mkdir -p "$HOME/.local/bin"
  if [ -r "$HOME_REAL_BIN/claude-day-projection.sh" ]; then
    ln -sf "$HOME_REAL_BIN/claude-day-projection.sh" "$HOME/.local/bin/claude-day-projection.sh"
  fi
}

# Number of times the stub was invoked for a given ccusage subcommand,
# counting the `claude <sub>` form the panel actually uses as well as a bare
# one, so a check cannot pass by counting a query shape nobody makes.
calls_for() { grep -cE "^(claude )?$1 " "$CCUSAGE_CALL_LOG" 2>/dev/null || true; }

# Seed the merged daily/weekly/monthly report the loop normally fetches once
# per slow tick. Checks that read recent_sections() must go through this, or
# they read an empty memo and assert nothing.
seed_recent() { RECENT_JSON=$(recent_sections_fetch); }

# Load the panel's functions without entering its render loop.
load_panel() { # $@ = panel args
  PANEL_LIB_ONLY=1 source "$PANEL_SH" "$@" </dev/null
  # Stable alias: checks that reach into the cache directly should not have
  # to know which of the panel's globals happens to name it this month.
  CCUSAGE_CACHE_DIR_REAL="$CCUSAGE_CACHE_DIR"
}

# Local midnight for a given YYYY-MM-DD, as an epoch. Tests that cross a day
# boundary have to use LOCAL midnight: the panel groups by local date, so a
# UTC-midnight epoch would cross the boundary at the wrong moment on every
# machine that is not on UTC -- which is every machine this runs on.
local_midnight() { # $1 = YYYY-MM-DD
  date -j -f '%Y-%m-%d %H:%M:%S' "$1 00:00:00" +%s
}
