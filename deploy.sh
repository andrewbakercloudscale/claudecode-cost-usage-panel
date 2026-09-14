#!/usr/bin/env bash
# Deploy the panel installer to this machine.
#
# There's no remote server here — the installer already writes straight to
# ~/.local/bin, ~/.zshrc, ~/.config/ghostty/config, and ~/.claude/settings.json,
# so "deploy" means "run the installer again to pick up the latest script
# changes." It's idempotent (see README's "Idempotent" note), so re-running
# after every edit is always safe.
#
# It took a `claude`/`opencode`/`all` argument until the OpenCode panel moved
# to its own repo (opencode-cost-usage-panel). `bash deploy.sh claude` is still
# accepted, because the README, the troubleshooting notes and a year of muscle
# memory all say it -- silently doing nothing for a word that used to work is
# the failure this project is about.
#
# Usage:
#   bash deploy.sh
#   bash deploy.sh claude     # accepted; same thing

set -euo pipefail

main() {
  local target="${1:-claude}"
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  case "$target" in
    claude|all) ;;
    opencode)
      echo "The OpenCode panel now lives in its own repo:" >&2
      echo "  https://github.com/andrewbakercloudscale/opencode-cost-usage-panel" >&2
      echo "Run 'bash deploy.sh' there instead." >&2
      exit 1
      ;;
    *)
      echo "usage: bash deploy.sh [claude]" >&2
      exit 1
      ;;
  esac

  echo "==> Deploying Claude Code panel..."
  bash "$dir/claude-panel-setup.sh"

  echo
  echo "Deploy complete."
}

main "$@"
