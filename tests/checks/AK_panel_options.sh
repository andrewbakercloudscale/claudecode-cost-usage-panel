# Check AK -- install-time options default to off and parse leniently.
#
# ~/.config/claude-panel/options carries CLAUDE_PANEL_CAFFEINATE and
# CLAUDE_PANEL_REMOTE_CONTROL. Both change what runs on the machine (a
# power assertion, a session reachable from claude.ai), so "no file", "no
# key" and anything unrecognised must all read as false; only an explicit
# true/1/yes/on turns one on. The environment wins over the file, so a
# single launch can override it.
check_AK_panel_options() {
  sandbox_new AK
  load_panel 10 12 ""
  local f="$HOME/.config/claude-panel/options"

  panel_option CLAUDE_PANEL_CAFFEINATE && assert_eq "no file reads as false" "off" "on"
  mkdir -p "$(dirname "$f")"
  printf '# comment\nCLAUDE_PANEL_REMOTE_CONTROL=true\n' > "$f"
  panel_option CLAUDE_PANEL_CAFFEINATE && assert_eq "a missing key reads as false" "off" "on"

  local v
  for v in true TRUE '"true"' "'yes'" 1 on; do
    printf 'CLAUDE_PANEL_CAFFEINATE=%s\n' "$v" > "$f"
    assert_eq "$v reads as true" "0" "$(panel_option CLAUDE_PANEL_CAFFEINATE; echo $?)"
  done
  for v in false 0 no off '' maybe; do
    printf 'CLAUDE_PANEL_CAFFEINATE=%s\n' "$v" > "$f"
    assert_eq "'$v' reads as false" "1" "$(panel_option CLAUDE_PANEL_CAFFEINATE; echo $?)"
  done

  printf 'CLAUDE_PANEL_CAFFEINATE=false\nCLAUDE_PANEL_CAFFEINATE=true\n' > "$f"
  assert_eq "the last assignment wins" "0" "$(panel_option CLAUDE_PANEL_CAFFEINATE; echo $?)"
  assert_eq "the environment overrides the file" "1" \
    "$(CLAUDE_PANEL_CAFFEINATE=false panel_option CLAUDE_PANEL_CAFFEINATE; echo $?)"
}
