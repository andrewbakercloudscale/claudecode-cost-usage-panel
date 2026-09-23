# Check N -- the two PRICES tables must not drift apart.
#
# The panel carries the same price table twice, in two standalone python
# heredocs (the hourly-bucket scan and the turn parser), "kept in sync
# manually" -- each heredoc is its own process and cannot import the other.
# That is a documented, accepted duplication. It is also exactly the setup
# that produced the stale context-window list this repo already paid for
# once, so it gets a guard rather than a comment.
check_N_price_table_parity() {
  sandbox_new N
  local n
  n=$(grep -c '^PRICES = {' "$PANEL_SH")
  assert_eq "there are exactly two price tables to compare" "2" "$n"

  local a b
  a=$(awk '/^PRICES = \{/{f++; next} f==1 && /^\}/{exit} f==1' "$PANEL_SH" | sed 's/#.*//' | tr -d ' ' | sort)
  b=$(awk '/^PRICES = \{/{f++} f==2 && /^\}/{exit} f==2 && !/^PRICES = \{/' "$PANEL_SH" | sed 's/#.*//' | tr -d ' ' | sort)
  assert_ne "the first table is non-empty" "" "$a"
  assert_eq "both tables list the same models at the same rates" "$a" "$b"

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
  local ca cb
  ca=$(awk '/^CACHE_READ_PRICE = \{/{f++; next} f==1 && /^\}/{exit} f==1' "$PANEL_SH" | tr -d ' ' | sort)
  cb=$(awk '/^CACHE_READ_PRICE = \{/{f++; next} f==2 && /^\}/{exit} f==2' "$PANEL_SH" | tr -d ' ' | sort)
  assert_eq "both cache-read override tables agree" "$ca" "$cb"
  assert_contains "Opus 5.5 cache reads at 0.20" '"claude-opus-5-5":0.20,' "$ca"
}
