# Check AJ -- a model ccusage prices at $0 is priced from the transcripts.
#
# ccusage bundles its price table with the release, so a model newer than
# the installed ccusage costs exactly $0 with its tokens still counted. On
# 2026-09-23 that was Claude Opus 5.5 (a day of it as `opus-5-5: $0`) and,
# unnoticed until the fix, Claude Fable 5.1 -- $534 of September missing
# from Month. backfill_unpriced re-prices those from ~/.claude/projects with
# the panel's own table, 1h cache writes at 2x (which ccusage's aggregate
# totals cannot distinguish from 5m writes).
#
# Asserted: the daily, weekly and monthly rows all gain the same figure, a
# model ccusage DID price keeps ccusage's number, and a model nobody can
# price stays at $0 so unpriced_models still flags it.
check_AJ_unpriced_backfill() {
  sandbox_new AJ
  local tp="$HOME/.claude/projects/test-project/sess.jsonl"
  # Midday UTC, so the local date is the same in any timezone this runs in.
  # One Opus 5.5 message logged twice (two content blocks, same usage) --
  # it must be counted once.
  #   1M input at $4 = 4.00; 1M 1h-cache-write at 4*2 = 8.00;
  #   1M cache read at 0.20 = 0.20; 0.1M output at $20 = 2.00  -> 14.20
  local opus='{"type":"assistant","timestamp":"2026-09-22T12:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":100000,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":1000000,"cache_creation":{"ephemeral_1h_input_tokens":1000000,"ephemeral_5m_input_tokens":0}}}}'
  local sonnet='{"type":"assistant","timestamp":"2026-09-22T12:00:00.000Z","requestId":"r2","message":{"id":"m2","model":"claude-sonnet-5","usage":{"input_tokens":1000000,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  local nonesuch='{"type":"assistant","timestamp":"2026-09-22T12:00:00.000Z","requestId":"r3","message":{"id":"m3","model":"claude-nonesuch-9","usage":{"input_tokens":1000000,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'
  printf '%s\n%s\n%s\n%s\n' "$opus" "$opus" "$sonnet" "$nonesuch" > "$tp"

  # Sonnet at a ccusage figure deliberately unlike its transcript price
  # ($2.00), so "kept ccusage's number" is distinguishable from "re-priced".
  local bd='[{"modelName":"claude-sonnet-5","cost":5.00,"inputTokens":1000000},
            {"modelName":"claude-opus-5-5","cost":0,"inputTokens":1000000,"outputTokens":100000,"cacheCreationTokens":1000000,"cacheReadTokens":1000000},
            {"modelName":"claude-nonesuch-9","cost":0,"inputTokens":1000000}]'
  printf '{"daily":[{"date":"2026-09-22","totalCost":5.00,"modelBreakdowns":%s}]}\n' "$bd" \
    > "$CCUSAGE_FIXTURE_DIR/daily.json"
  printf '{"weekly":[{"week":"2026-09-20","totalCost":5.00,"modelBreakdowns":%s}]}\n' "$bd" \
    > "$CCUSAGE_FIXTURE_DIR/weekly.json"
  printf '{"monthly":[{"month":"2026-09","totalCost":5.00,"modelBreakdowns":%s}]}\n' "$bd" \
    > "$CCUSAGE_FIXTURE_DIR/monthly.json"

  load_panel 10 12 ""
  seed_recent
  local r; r=$(recent_sections)
  local k
  _aj() { printf '%.2f' "$(jq -r "$1" <<<"$r")"; }
  for k in daily weekly monthly; do
    assert_eq "$k: Opus 5.5 priced from the transcript, deduplicated" "14.20" \
      "$(_aj ".$k[0].modelBreakdowns[] | select(.modelName==\"claude-opus-5-5\") | .cost")"
    assert_eq "$k: a model ccusage priced keeps ccusage's figure" "5.00" \
      "$(_aj ".$k[0].modelBreakdowns[] | select(.modelName==\"claude-sonnet-5\") | .cost")"
    assert_eq "$k: the row total includes the backfill" "19.20" \
      "$(_aj ".$k[0].totalCost")"
  done
  assert_eq "a model nobody can price is still flagged" "claude-nonesuch-9" \
    "$(unpriced_models "$r")"
}
