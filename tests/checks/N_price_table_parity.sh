# Check N -- the two PRICES tables must not drift apart.
#
# The panel carries the same price table three times, in standalone python
# heredocs (the hourly-bucket scan, the ccusage $0 backfill and the turn
# parser), "kept in sync manually" -- each heredoc is its own process and
# cannot import the others.
# That is a documented, accepted duplication. It is also exactly the setup
# that produced the stale context-window list this repo already paid for
# once, so it gets a guard rather than a comment.
check_N_price_table_parity() {
  sandbox_new N
  local n
  n=$(grep -c '^PRICES = {' "$PANEL_SH")
  assert_eq "there are exactly three price tables to compare" "3" "$n"

  # Table $1 (1-based), comments and spacing stripped, sorted.
  _n_table() {
    awk -v k="$1" -v re="^$2 = \\{" '$0 ~ re {f++; next} f==k && /^\}/{exit} f==k' "$PANEL_SH" \
      | sed 's/#.*//' | tr -d ' ' | sort
  }
  local a b c
  a=$(_n_table 1 PRICES); b=$(_n_table 2 PRICES); c=$(_n_table 3 PRICES)
  assert_ne "the first table is non-empty" "" "$a"
  assert_eq "tables 1 and 2 list the same models at the same rates" "$a" "$b"
  assert_eq "tables 1 and 3 list the same models at the same rates" "$a" "$c"

  # Rates verified against the claude-api skill's model table (cached
  # 2026-06-24). Spot-check the ones whose absence or drift would be
  # expensive rather than every row -- the parity assertion above covers
  # the rest.
  assert_contains "Opus 5 at 5/25"      '"claude-opus-5":(5.00,25.00),' "$a"
  assert_contains "Opus 5.5 at 4/20"    '"claude-opus-5-5":(4.00,20.00),' "$a"
  assert_contains "Sonnet 5 at 2/10"    '"claude-sonnet-5":(2.00,10.00),' "$a"
  assert_contains "Haiku 4.5 at 1/5"    '"claude-haiku-4-5":(1.00,5.00),' "$a"
  assert_contains "Fable 5.1 at 10/50"  '"claude-fable-5-1":(10.00,50.00),' "$a"
  assert_contains "Mythos 5.1 at 10/50" '"claude-mythos-5-1":(10.00,50.00),' "$a"

  # The cache-read overrides are duplicated the same way, and a missing one
  # overstates a cache-heavy session by ~50% (Opus 5.5 reads at 0.05x).
  local ca cb cc
  ca=$(_n_table 1 CACHE_READ_PRICE); cb=$(_n_table 2 CACHE_READ_PRICE); cc=$(_n_table 3 CACHE_READ_PRICE)
  assert_eq "cache-read override tables 1 and 2 agree" "$ca" "$cb"
  assert_eq "cache-read override tables 1 and 3 agree" "$ca" "$cc"
  assert_contains "Opus 5.5 cache reads at 0.20" '"claude-opus-5-5":0.20,' "$ca"
}
