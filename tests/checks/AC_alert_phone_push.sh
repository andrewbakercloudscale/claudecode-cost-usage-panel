# Check AC -- the phone push is the only channel that reaches you when you
# are away from the machine, so its failure modes are the ones that matter.
#
# The other two channels are self-announcing: a broken chat line is visible
# in the chat, a broken bell is audible at the desk. A Telegram send that has
# quietly stopped working is invisible by construction -- you find out by not
# being told about a $200 session. That asymmetry is why this check exists
# and why it is mostly about the failure paths rather than the happy one.
check_AC_alert_phone_push() {
  sandbox_new AC
  local hook="$HOME_REAL_BIN/claude-cost-alert-check.sh"
  if [ ! -f "$hook" ]; then
    assert_eq "cost-alert hook is present to be checked" "1" "0"
    return
  fi

  printf '%s\n' '{"sessions":[{"period":"S1","totalCost":8.0},{"period":"S2","totalCost":8.0},{"period":"S3","totalCost":8.6},{"period":"SID-AC","totalCost":42.13}]}' \
    > "$CCUSAGE_FIXTURE_DIR/session.json"
  local payload='{"session_id":"SID-AC","cwd":"/Users/x/Desktop/github/claudecode-cost-usage-panel"}'

  # A capturing curl, so the check exercises the real send path without
  # sending anything. Ahead of the sandbox's stub dir on PATH.
  local bin="$SBX/bin"
  mkdir -p "$bin"
  export CURL_CAPTURE="$SBX/curl.log"
  : > "$CURL_CAPTURE"
  cat > "$bin/curl" <<'STUB'
#!/usr/bin/env bash
{ echo "ARGS: $*"
  for a in "$@"; do case "$a" in text@*) echo "BODY:"; cat "${a#text@}" ;; esac; done
} >> "$CURL_CAPTURE"
STUB
  chmod +x "$bin/curl"

  # ---- credentials missing -------------------------------------------------
  # The one case the operator must be told about, because every other symptom
  # of it is silence. It is surfaced in the chat line, which still works.
  local out_nocreds
  out_nocreds=$(PATH="$bin:$PATH" TERM_PROGRAM=ghostty bash "$hook" <<<"$payload")
  assert_contains "missing creds are announced in the chat line" \
    "no phone push sent" "$(jq -r '.systemMessage' <<<"$out_nocreds")"
  assert_eq "and nothing is sent" "0" "$(wc -c < "$CURL_CAPTURE" | tr -d ' ')"
  # That notice is for the operator at the keyboard, not for the model and
  # not for a desktop popup.
  assert_not_contains "the notice does not leak into the model's context" \
    "no phone push sent" "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out_nocreds")"

  # ---- credentials present -------------------------------------------------
  mkdir -p "$HOME/Desktop/github"
  printf 'export TELEGRAM_BOT_TOKEN=FAKE:TOKEN\nexport TELEGRAM_CHAT_ID=99999\n' \
    > "$HOME/Desktop/github/.creds"
  rm -f "$HOME/.cache/claude-cost-alert-state/SID-AC.json"
  : > "$CURL_CAPTURE"

  local out_creds
  out_creds=$(PATH="$bin:$PATH" TERM_PROGRAM=ghostty bash "$hook" <<<"$payload")
  # The send is detached so the hook can return inside its 5s timeout; that
  # is the whole point, so the check has to wait for it rather than assume it.
  local waited=0
  while [ ! -s "$CURL_CAPTURE" ] && [ "$waited" -lt 50 ]; do
    sleep 0.1; waited=$(( waited + 1 ))
  done
  local sent; sent=$(cat "$CURL_CAPTURE")

  assert_contains "a message is sent to Telegram" "api.telegram.org" "$sent"
  assert_not_contains "no missing-creds notice when they are present" \
    "no phone push sent" "$(jq -r '.systemMessage' <<<"$out_creds")"
  # $42.13 against an $8.20 baseline is 5.1x -- purple, not red. It reads as
  # red only if the current session is wrongly left in its own baseline.
  assert_contains "the phone gets the headline" "RUNAWAY COST" "$sent"
  assert_contains "with the figure" '$42.13' "$sent"
  # Several sessions run at once here; a push that does not say which one it
  # is about cannot be acted on from a phone.
  assert_contains "and says which project" "claudecode-cost-usage-panel" "$sent"
  assert_contains "and which session" "session: SID-AC" "$sent"

  # The body travels in a file, not on the argv, so it never shows up in
  # `ps` -- and neither does anything else about the alert.
  assert_contains "the body is passed by file reference" "text@" "$sent"

  # ---- opt-out -------------------------------------------------------------
  rm -f "$HOME/.cache/claude-cost-alert-state/SID-AC.json"
  : > "$CURL_CAPTURE"
  local out_off
  out_off=$(PATH="$bin:$PATH" TERM_PROGRAM=ghostty CLAUDE_COST_ALERT_TELEGRAM=0 \
    bash "$hook" <<<"$payload")
  sleep 0.5
  assert_eq "CLAUDE_COST_ALERT_TELEGRAM=0 sends nothing" "0" \
    "$(wc -c < "$CURL_CAPTURE" | tr -d ' ')"
  # Deliberately silent: an opt-out that nags is one you route to /dev/null.
  assert_not_contains "and does not nag about it" "no phone push sent" \
    "$(jq -r '.systemMessage' <<<"$out_off")"

  # ---- the throttle still governs the push --------------------------------
  # Without this the push would be per-PROMPT rather than per-escalation,
  # which is how a useful alert becomes one you mute.
  : > "$CURL_CAPTURE"
  PATH="$bin:$PATH" TERM_PROGRAM=ghostty bash "$hook" <<<"$payload" >/dev/null
  sleep 0.5
  assert_eq "a second prompt at the same tier pushes nothing" "0" \
    "$(wc -c < "$CURL_CAPTURE" | tr -d ' ')"

  unset CURL_CAPTURE
}
