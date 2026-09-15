# Claude Code Cost & Usage Panel

Live, always-visible cost and token tracking for **[Claude Code](https://claude.com/claude-code)**, running in a right-hand [Ghostty](https://ghostty.org/) split next to your terminal session — so you can watch what a coding agent is actually costing you, turn by turn, instead of finding out at the end of the month.

This came out of a simple problem: AI coding agents burn tokens and money per turn, per session, per day — and none of that is visible while you're working. You only find out later, from a dashboard or an invoice, by which point the expensive session is long over and you've learned nothing you can act on. This repo is the fix: a live panel that sits next to your terminal and updates every few seconds.

The same panel for OpenCode lives in **[opencode-cost-usage-panel](https://github.com/andrewbakercloudscale/opencode-cost-usage-panel)** — the two were one repo until they were split apart, which is why the design notes here and there cross-reference each other.

Full write-up and motivation: **[AI coding costs are guesswork without this: instrumenting OpenCode and Claude Code](https://andrewbaker.ninja/2026/08/22/ai-coding-costs-are-guesswork-without-this-instrumenting-opencode-and-claude-code/)**

## What you get

`claude-panel-setup.sh` installs a live panel for Claude Code, built on top of [`ccusage`](https://github.com/ryoppippi/ccusage):

- **Per-turn breakdown of the current session** — turn number, model, context size, context growth (Δ) since the last turn, cache hit %, and estimated cost per turn, read straight out of the session transcript and priced against Anthropic's published per-model rates (including cache read/write multipliers).
- **Live status line** — current session value, today's value, active-block burn rate, 7-day average session cost, 30-day value, and the current project folder. ("Value" because these are priced at pay-as-you-go API rates regardless of what plan you're actually on — see note below.)
- **Active block** — start/end time, value so far, burn rate ($/hr and tokens/min, color-coded green/yellow/red), and a projected total for the block.
- **Today** — total cost/tokens, input/output split, cache new/read split, and a per-model breakdown.
- **Last 3 days** — a simple cost bar chart.
- **Week / month totals.**
- **Top 5 sessions today** by cost.

Everything through the per-turn table is always shown in full; sections below it fill whatever pane height is left, so a short split never truncates the part you actually care about.

Also installs a **session-pin hook** (`claude-panel-session-hook.sh`, wired into Claude Code's `SessionStart` hook) that records which session is running in which directory, so the panel opens the right transcript instead of guessing — see "How it works" below.

Also installs a **cost-alert hook** (`claude-cost-alert-check.sh`, wired into Claude Code's `UserPromptSubmit` hook) that posts a warning *into the chat itself* — so it works over Remote Control too, not just locally — when the current session's cost crosses 2x (red) or 3x (purple) your 7-day average session cost, or when the panel failed to auto-launch for this window. There are three independent rules — a **per-session** one (this session vs your recent sessions), a **bad-day** one (today's *projected* total against a 2-sigma line, early enough to act on) and a **runaway-day** one (actual spend against a 3-sigma line). They read:

```
UserPromptSubmit says: 🟠 BAD DAY AHEAD — heading for $131.45 today, over your $127.29 2σ line ($71.20 spent so far)
UserPromptSubmit says: 🟥 DAILY SPEND — $412.10 today, over your $373.44 3σ limit (mean $114.77 over 13 days)
UserPromptSubmit says: 🔴 COST ALERT — $20.00 this session, 2.4x your $8.20 average
UserPromptSubmit says: 🟣 RUNAWAY COST — $61.00 this session, 7.4x your $8.20 average — consider wrapping up or starting a fresh session
```

On Ghostty it also fires a real macOS desktop notification (OSC 777) alongside the chat line; every other terminal gets a bell. And it **pushes to Telegram**, which is the only one of the three channels that will reach a phone you aren't currently looking at — credentials come from the shared `~/Desktop/github/.creds` (`TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID`), the same store the Pi watchdogs use. Set `CLAUDE_COST_ALERT_TELEGRAM=0` to turn the push off; `bash check-panel-status.sh` reports whether it's configured and whether any sends have failed.

### Launching

- **Auto-launch on first use per window.** A `preexec` hook in `~/.zshrc` watches for the first `claude...` command typed in a terminal window and opens the panel automatically — you never have to remember to start it.
- **tmux-aware.** If you're inside a tmux session, the launcher uses tmux's own `split-window` instead of driving Ghostty via AppleScript — no Accessibility permission or keystroke simulation needed. This matters because tmux overrides `$TERM_PROGRAM` to `tmux` regardless of the outer terminal, so without this check the Ghostty path below would silently fail to detect Ghostty even when Ghostty is the real host.
- **Auto-resize** to roughly 1/3 of the window width — via tmux's `split-window -l 33%` inside tmux, or Ghostty keybinds (`ctrl+shift+h` / `ctrl+shift+l`, added to `~/.config/ghostty/config` if missing) otherwise — then focus returns to your original pane.
- **Verified, not assumed (Ghostty path).** The launcher drives Ghostty via `osascript`/System Events, retries up to 3 times, and confirms success by checking that a new panel *process* actually exists — not just that AppleScript returned exit code 0, which it will happily do even when nothing happened.
- **Logged.** Every launch attempt is logged with a shared run ID (`~/.cache/claude-panel-launch.log`) so a failed auto-launch is diagnosable instead of just silently missing.
- **Idempotent.** Safe to re-run any time — it overwrites the generated scripts with the latest version and skips any `.zshrc`/config block that's already present.
- **Finder Service aware.** If you launch Claude Code via a Finder Service / Automator workflow (`ghostty-claude-launcher`) rather than an interactive shell, the installer patches that script too, since the `preexec` hook never fires for it.

## How it works

The installer lays down a **panel script** (the thing that renders live stats in a loop) and a **launcher script** (the thing that opens a Ghostty split and starts the panel in it), plus a small `~/.zshrc` hook that fires the launcher automatically. A few decisions in there aren't obvious from the code alone:

- **Per-turn cost isn't available from Claude Code's own tooling, so the panel computes it itself.** `ccusage` only exposes session/day/block-level totals, not a per-message figure. The panel instead reads the raw session transcript directly (`~/.claude/projects/*/*.jsonl`) and prices every assistant turn from its token usage: input, output, cache read, and cache write tokens, each at Anthropic's published per-model rate (cache read at 0.1x the input rate, cache write at 1.25x/2x for 5-minute/1-hour cache). That's what makes the "per turn" table possible — it doesn't exist anywhere else.
- **The context-window math is fragile in a specific way, and the code works around it.** The panel needs the *real* session ID and model ID from the transcript — a placeholder ID silently returns a `$0.00` session cost instead of erroring, and an unset model ID makes `ccusage` assume an old 200k context window instead of Sonnet 5's actual 1M, which makes context usage read as `>100%`. Both failure modes are silent, which is exactly the kind of thing this project exists to prevent, so the panel derives both IDs from the transcript itself rather than trusting a default.
- **Rendering never trusts the pane's current size to stay put.** The panel is meant to sit in a resizable split, so every frame is measured against the *current* terminal width/height (`tput cols`/`tput lines`) rather than a fixed layout, and every printed line is padded with `\033[K` (clear-to-end-of-line) so a shorter new frame can't leave stale characters from a wider previous one ghosting through. It goes further still: the per-turn table is rendered as a "guaranteed" block that's never truncated, and only the sections below it (active block, today, trends, top sessions) compete for whatever pane height is left — so asking for the last 20 turns always means 20 turns, never "20 turns if there's room."
- **The AppleScript automation verifies itself instead of trusting its own exit code.** The launcher drives Ghostty via `osascript`/System Events to open a split, type the panel command, and resize the pane. AppleScript will report success (exit 0, no stderr) even when a stale frontmost check or an internal early `return` meant nothing actually happened — so the launcher doesn't believe it. It snapshots running panel processes before the attempt, snapshots them again after, and only calls it a success if a *new* process actually appeared. It retries up to 3 times and logs every attempt (with a shared run ID, so concurrent window opens don't interleave into an unreadable log) to `~/.cache/claude-panel-launch.log`.
- **The panel is told which session it is watching; it does not work it out.** A project directory holds every transcript that directory has ever produced, so "which of these is the conversation in the pane next to me" has no answer the panel can compute — two `claude` sessions open in one directory are indistinguishable by file. The answer is written down instead: `claude-panel-session-hook.sh` fires on Claude Code's `SessionStart` event and writes `<session-id>` where the panel can read it on every tick. Because the hook runs *inside* the session, it is authoritative rather than predictive — it covers `--resume`, `--continue`, GUI windows and IDE terminals, none of which the `~/.zshrc` `preexec` hook can pin in advance. The launcher writes the same thing for the id it chose, so the pin still works with hooks disabled.
- **The pin is addressed to a pane, not to a directory.** `~/.cache/claude-panel-pin/tty/<claude-tty>` holds the session id; `~/.cache/claude-panel-pin/pane/<panel-tty>` holds `<claude-tty>  <panel-pid>`, written by the launcher — the one process that ever sees both halves, because it runs in the claude pane's own shell and then watches the new panel appear. `~/.cache/claude-panel-pin/<project-dir>` still exists and is still read, but only by a panel with no pairing (started by hand, or through a path with no launcher).

  The directory key was wrong the moment a repo had two sessions open at once, which is the ordinary case here. Every launch overwrote the one pin every panel in that directory read, so all of them followed whichever session started last: on 2026-09-08 a panel adopted a second pane's session within a second of it opening and spent the night reporting that conversation's turns and cost as its own, and the next morning all three panels in that repo adopted a window that had been opened and never typed into — no transcript, so "no active Claude Code session found", permanently, against sessions live in the splits beside them. A pane hosts exactly one session at a time, so keying on the pane answers both. The panel refuses a pairing that names a different pid: terminal names are recycled, and without that check the next split to hold `ttys004` inherits the last one's claude.

- **A session with no pane writes no pin, and a pin is believed only while its session is alive.** The `SessionStart` hook fires for every session Claude Code starts, and most of them are nobody's pane: `claude --print` is how the standards-review sections run, how build scripts shell out to the CLI, how a hook spawns a one-shot. The hook now answers "which pane is this?" by walking up to the **first `claude` in its own ancestry** and taking that process's controlling terminal — none, and it writes neither pin and says so in the log. On the panel's side, a pin whose transcript has not been written to for `PANEL_PIN_DEAD` seconds (default: the same half hour that admits one) is released rather than held for the life of the pane, and a directory-keyed pin stands aside when it names something other than the one live *pane* session in that directory.

  All three halves of that failed together on 2026-09-14 in `wordpress-backup-restore-plugin`. A build ran two review sections at 16:14:30; both wrote the directory pin; the panel beside a 1080-turn Opus session adopted the second one three seconds later, and half an hour after that review had finished it was still reporting it as this pane's session — `Model: Sonnet 5`, `$0.30`, `9%` context, a three-row turn table — while the session it was watching ran on at `$38/hr` in the split beside it. The model line is what gave it away; every other figure was wrong in exactly the same way and looked entirely plausible. The tty pin was worse and nobody had noticed it at all: the old walk stopped at the first process with *any* terminal, which for a headless claude is not the claude but the interactive shell that started the build — so an ordinary build wrote a **pane** pin, the strongest channel there is, against the pane of the session that launched it.

- **Which pane a panel is in, and whether a session is over, are questions about processes — so they are asked of the process table.** Every pane in a Ghostty window descends from that window's own `ghostty … -e ghostty-claude-launcher <dir>` process: the panel through `login → zsh → ccusage-panel.sh`, its claude through `login → ghostty-claude-launcher → claude`. So a panel with no pairing file walks up to its window, looks for the one claude that descends from the same window, and takes its terminal — the same pairing the launcher writes, derived from the live process tree instead of from a note somebody managed to write down in time. Two claude panes in one window pairs nothing, and inside tmux the walk declines outright (every pane there descends from the one shared server, so it would answer "all of them"). And a pin is released only when its transcript has been quiet for `PANEL_PIN_DEAD` seconds **and** no process is running that session — `--session-id` on a live command line, or a tty pin whose pane still holds a claude.

  Both halves were indirect until 2026-09-15, and both were wrong that morning in this repo. The launcher writes its pairing from a `pgrep` that has to find the panel first, and when it misses there is no second try: two of the three panels open here had no pairing file at all and had spent their lives on the directory-keyed pin, which names a **repo**. Then the liveness test — transcript mtime — fired on a session that was merely idle. A transcript stops growing the moment a session stops being *typed into*, so at 10:29:13 both panels dropped a live session for having been quiet since 09:59, showed `no active Claude Code session found` for eighteen minutes beside the conversation they were reporting on, and at 10:47:04 adopted a session from a **different window**: the release added to prevent a misattribution caused one. `claude` pid 54674 was running throughout, in the pane whose panel had gone blank — and `ps` had said so all along, along with which window it shared with that panel.

  This replaced passing the session id on the panel's command line, which meant the *launcher typed it* into the new split as synthetic keystrokes. That is not a lossless channel. An observed pane ran with `9e435181h-888e-4f0c-811-3befb80226t3d` against a real id of `9e435181-888e-4f0c-81f1-3befb802263d` — an `h` and a `t` woven in from the real keyboard, an `f` lost — which names a transcript that will never exist, so it showed `Model: Unknown` and `no active Claude Code session found` for five hours while every account-wide figure beside it stayed correct. A file cannot be corrupted that way, and because it persists, a panel restarted mid-conversation reads the same answer it would have had at launch — the case the old "newest transcript born after the panel started" fallback structurally could not see.

- **The cost-alert hook is a second, independent instrumentation path.** `claude-cost-alert-check.sh` hooks into Claude Code's own `UserPromptSubmit` event and posts straight into the chat transcript via `systemMessage` — which is what makes it work over Remote Control, where a local desktop notification wouldn't reach you. It's throttled per session (state kept in `~/.cache/claude-cost-alert-state/<session_id>.json`) so it fires once per tier escalation rather than on every prompt, and it also surfaces launcher failures, so a broken panel doesn't fail silently either.

- **The message's shape is dictated by the renderer, which was measured rather than guessed.** Against Claude Code 2.1.266, `systemMessage` arrives as a `{"type":"system","subtype":"informational"}` event and *every line of it* is rendered with a literal `UserPromptSubmit says: ` prefix; markdown is not interpreted, but emoji are. So the alert is **one line per distinct alert**, never one alert wrapped over several — a three-line message repeats that 23-column prefix three times and pushes the figures off the right of a phone screen — and its emphasis is emoji and caps, with the severity word and the money first, because the front of the line is the part that reliably survives truncation. `tests/checks/AB_alert_message_shape.sh` holds that shape.

- **The bad-day rule fires on the *projection*, which is the only version of this alert you can act on.** A day total can only be judged once it has been spent, so an actual-spend rule is structurally a postmortem. The projection comes from your own hour-of-day spend pattern (`claude-hourly-buckets.json`), scaled by how today's pace compares with a typical day's — not a flat extrapolation of the live burn rate, which spikes 10x after one pricey turn and decays within minutes. Both the panel's "by EOD" figure and this alert now come from **one** file, `claude-day-projection.sh`: a panel drawing one number while an alert fires on another is drift with consequences, so both refuse to start without it rather than silently falling back.

- **The projection stands down below 25% of a typical day, measured in spend rather than clock.** Those hours are not equally productive: at 09:00 a normal day has barely started spending, so a $40 morning scales to a preposterous total and would flag a day that then goes quiet. And because only the *panel* writes the hourly buckets, a machine where the panel has never run has no projection at all — in which case the bad-day rule is not merely quiet, it is **off**, and `check-panel-status.sh` says so outright.

- **Two claims, not one**, so the early warning doesn't consume the later one: a day flagged at 14:00 that then genuinely blows past the 3-sigma line at 19:00 is two different pieces of news. When both would fire at once only the louder is sent — the actual limit sits above the projected one, so crossing it means the day was always going to be flagged.

- **The daily rules exist because the session rule structurally cannot see a bad day.** The session rule compares *one* session against the average session, so a day made of twenty ordinary sessions never trips it however much it totals — you can spend $150 across a day in silence. The daily rule is `mean + 3·sd` over the preceding days (sample sd, days with no activity simply absent rather than counted as zero), throttled once per calendar day and claimed with an atomic `mkdir` so that N open windows raise one alert rather than N.

- **The window does more work than the sigma multiplier, which is not obvious and cost a round of tuning to find.** sd here is about the size of the mean, so the limit is set largely by *which days are in view*. On a 30-day window mean+3σ was **$775.56** and exactly one day in that window cleared it — the window still carried a heavy fortnight from August. The same rule on a rolling **14 days** sits near $370 and does catch the outliers. Backtested over 24 days of real history: mean+3σ fired once, mean+2σ once, mean+1σ three times, 2× median five times, 1.5× median eight. The window is therefore 14 days, and `bash check-panel-status.sh` prints both live limits plus the sample behind them — a threshold nobody can see is one nobody can tell has stopped being reachable. Fewer than 7 days worked disables both rules outright and says so, rather than acting on an sd computed from three days.

- **A session is no longer counted in its own baseline.** It was, and that is self-defeating in exactly the case the alert exists for: a runaway session is a member of the set whose average it is measured against, so the further it runs the higher it drags the bar it must clear. Measured on a $42.13 session against three ~$8 ones, including it reported *"2.5x a $16.68 average"* where the honest answer is *5.1x an $8.20 average* — red instead of purple. With a per-tier throttle, a fire at the wrong tier can mean the real crossing is never reported at all.

- **The phone push fails silently by construction, so its failure paths are what the tests are about.** A broken chat line is visible in the chat and a broken bell is audible at the desk; a Telegram send that has quietly stopped working announces itself only by *not* telling you about a $200 session. So missing credentials are reported in the chat line — the channel still working — rather than swallowed, the send is detached and backgrounded (this hook sits on the interactive path under a 5s timeout, and an unreachable `api.telegram.org` must add zero seconds to a prompt submission), the message travels via `--data-urlencode text@file` so it never appears in `ps`, and curl's stderr is discarded rather than logged because it can echo a URL containing the bot token. `tests/checks/AC_alert_phone_push.sh` covers the missing-creds, opt-out and throttle paths.

- **A hook cannot raise a push notification *itself*, and the near-miss is worth naming.** `terminalSequence` reaches the terminal (a Ghostty desktop notification here) but is explicitly discarded in the web app and in cloud sessions, so it never reaches a phone. The tempting alternative — put "call the PushNotification tool" in `additionalContext`, which *is* delivered to the model — was tried and does not work: a model correctly treats an instruction arriving from hook output as untrusted and declines it, so that route looks wired up and silently does nothing. `additionalContext` is therefore kept purely descriptive. A genuine phone push has to leave the machine by a route the hook calls itself, which is what the Telegram send above is.
- **Everything is idempotent by construction.** Each installer checks for its own marker (a comment string in `~/.zshrc`, a `jq` query against `~/.claude/settings.json`, a grep against `~/.config/ghostty/config`) before appending anything, so re-running an installer after a script update never double-installs a hook or duplicates a keybind.

## Requirements

- macOS + [Ghostty](https://ghostty.org/) for the auto-split part — unless you run inside tmux, in which case tmux's own split is used instead and Ghostty isn't required. The panel script itself works in any terminal if you just run it manually.
- `jq`
- Node.js (for [`ccusage`](https://github.com/ryoppippi/ccusage)) and Python 3
- Accessibility permission granted to Ghostty (macOS will prompt the first time the launcher tries to drive it via System Events) — not needed for the tmux path

## Install

```bash
bash claude-panel-setup.sh
```

Or via the wrapper script:

```bash
bash deploy.sh
```

`deploy.sh` doesn't do anything the installer above doesn't already do on its own — there's no remote server for this repo, so "deploy" means re-running the installer to pick up the latest script changes on this machine. It's just a single command to re-run after pulling changes, mirroring the `deploy-*.sh` convention used elsewhere. Safe to re-run any time; the installer is idempotent. `bash deploy.sh claude` still works too — the argument existed while this repo also held the OpenCode panel, and quietly ignoring a word that used to mean something is the failure this project is about.

Then open a **new** terminal window/tab (or `source ~/.zshrc`) and type a `claude...` command — the panel opens automatically in a right-hand split.

You can also run the panel manually at any time, in any terminal:

```bash
~/.local/bin/ccusage-panel.sh [refresh_seconds] [turn_rows]
```

### Refresh tiers

The panel redraws on two clocks, and **each section header states its
own rate** so you can always see how old the number under it can be:

| Section | Default rate | Argument |
|---|---|---|
| `This Session` (per-turn table + burn rate) | 10s | `refresh_seconds` (arg 1) |
| Header summary, `Recent`, `Top Sessions Today` | 2m | `SLOW_REFRESH` env var |

The split exists because the two tiers cost wildly different amounts. The
per-turn table reads one transcript file and is cached on that file's own
mtime+size, so an idle pane re-renders it for free — it can afford to be
near-live. Everything else is built from `ccusage` reports, and every
`ccusage` invocation reparses the whole transcript corpus (hundreds of MB,
~0.3–1s of CPU each); at a single 10s tier an actively-used pane was paying
several of those *every ten seconds*, which is what made the fans spin.

```bash
# near-live turns, hourly summary
SLOW_REFRESH=3600 ~/.local/bin/ccusage-panel.sh 5 12

# everything slow, for a background monitor
SLOW_REFRESH=600 ~/.local/bin/ccusage-panel.sh 30 12
```

Both tiers sit behind a corpus-change gate: if nothing has been written under
`~/.claude/projects` since a cached answer was computed, that answer cannot
have changed, so the slow tier costs nothing at all on an idle pane no matter
how often it comes round. The block countdown and `$/hr` denominator are
derived locally from the block's own start/end timestamps, so they keep
moving between fetches without one.

## FAQ

- **Sonnet 5 (and Fable 5) burns through tokens much faster than Sonnet 4.6 did on the same kind of task — is there a way to cap it back to a 200k context window?** Yes. Set `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` in your shell profile. Claude Code then treats Sonnet 5 / Fable 5 as having a 200k context window instead of their native 1M, removes the 1M variant from the model picker, and — this is the part that actually matters for cost — **auto-compaction kicks in at the 200k boundary**, the same discipline that was implicitly keeping 4.6's token usage in check. You don't need to switch models back to get that behavior. The panel shows which cap is currently in effect (`🧭 Context cap: 200k (forced via CLAUDE_CODE_DISABLE_1M_CONTEXT)` vs `1M (native)`) so it's visible at a glance rather than something you have to remember you set.
- **`/context` shows 200k even though I selected Sonnet 5 — did it silently downgrade to 4.6?** Not necessarily. `/context` reports usage against whichever window is *currently active* for the session, and if `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` is set (or you're behind an LLM gateway that defaults Sonnet 5 to 200k), you'll correctly see a 200k ceiling while genuinely running Sonnet 5. Check the per-turn `Model` column in the panel — it reads the real model ID out of the transcript for every turn — rather than inferring the model from the context-window size alone.
- **Does the generic `sonnet` alias always mean the latest Sonnet?** It's provider-dependent, not a bug: on the Anthropic API directly, `sonnet` resolves to the latest Sonnet (Sonnet 5 as of this writing). On Claude Platform via AWS it currently resolves to Sonnet 4.6; on Bedrock/Google Cloud/Microsoft Foundry it resolves to Sonnet 4.5. If you want a specific version regardless of provider, select it explicitly rather than relying on the bare alias.

## Design & investigation notes

Longer write-ups of the work behind the current behaviour. Read these before
changing the areas they cover — each one records a bug that was shipped, and
in two cases shipped twice.

| Document | Covers |
|---|---|
| [`SLOW-TIER-PLAN.md`](SLOW-TIER-PLAN.md) | This panel's refresh tiers, caching, TTL buckets, error surfacing, and every gate that failed silently on the way. The rollout log at §10 is the index. |
| [`LAUNCHER-TARGETING.md`](LAUNCHER-TARGETING.md) | **Which window gets the panel**, and why that is a hard question. The panel is not bound to the terminal process — the launcher types keystrokes into whatever window has focus. Read this before touching the frontmost check. |
| [`OPTIMIZATION-PLAN.md`](OPTIMIZATION-PLAN.md) | Superseded by `SLOW-TIER-PLAN.md`; kept as the record of an investigation whose conclusion was right and whose attribution was wrong. |

Both of the remaining documents were written while the OpenCode panel shared
this repo and refer to it in places. The equivalent pass for that panel is
[`OPENCODE-TIER-PLAN.md`](https://github.com/andrewbakercloudscale/opencode-cost-usage-panel/blob/main/OPENCODE-TIER-PLAN.md),
which moved with it.

## Troubleshooting

- **Panel never opens automatically** — check `~/.cache/claude-panel-launch.log`. If you're outside tmux, the most common cause is Ghostty missing Accessibility permission (System Settings → Privacy & Security → Accessibility). If you're inside tmux, confirm `tmux` is actually on `$PATH` for that shell (the log will say `TMUX is set but tmux binary not found` if not).
- **A new window opens with no panel, but only sometimes** — mostly fixed. The launcher now addresses its keystrokes to its own Ghostty *process* (`CGEventPostToPid`), so focus is irrelevant and the split cannot land in another window. That needs pyobjc's Quartz bindings, which are not on stock macOS: `pip3 install pyobjc-framework-Quartz` (or use a Homebrew python) enables it, and `~/.cache/claude-panel-launch.log` says which path each run took. Without them the launcher uses the older focus-dependent path, which refuses to type when it cannot positively identify the focused window — safe, but occasionally no panel. Recover by running `~/.local/bin/ccusage-panel.sh` in a split yourself. Background in [`LAUNCHER-TARGETING.md`](LAUNCHER-TARGETING.md). — the launcher can only split the window that has keyboard focus, and it refuses to type when it cannot positively identify that window as the one it was launched from. With several Ghostty instances running that identification can be ambiguous, and it skips rather than risk typing a shell command into whatever you are working in. The log line names every instance it saw and which one held focus. Recover by running `~/.local/bin/ccusage-panel.sh` in a split yourself. Background in [`LAUNCHER-TARGETING.md`](LAUNCHER-TARGETING.md).
- **Split opens but stays 50/50** — outside tmux, make sure `~/.config/ghostty/config` has the `resize_split` keybinds the installer adds (`ctrl+shift+h` / `ctrl+shift+l`); if that file didn't exist when you installed, create it and re-run the installer. Inside tmux this shouldn't happen — the launcher opens the split at 1/3 width directly via `split-window -l 33%`.
- **`Model: Unknown` and `no active Claude Code session found`, while every other figure is correct** — the panel has not been told which transcript is this pane's. Check `~/.cache/claude-panel-pin.log`: it records every pin adopted, ignored or abandoned, and every pane pairing learned. If the log shows neither a `paired:` line (the launcher's file) nor a `paired by window:` line (the panel's own walk up to its Ghostty window) for this panel, it is falling back to the directory-keyed pin — which is shared with every other session in the repo, so a second window opened there is enough to point it somewhere else; the log then also records every pin `releas`ed for going cold with nothing running it, every one `keep`ing its session because that session's process is alive, and every one `declin`ed in favour of the one live pane session in the directory, which is how an unpaired panel recovers on its own. Confirm `~/.claude/settings.json` has the `SessionStart` hook (`jq '.hooks.SessionStart' ~/.claude/settings.json`) and that `~/.cache/claude-panel-pin/tty/<your-claude-tty>` (`ps -o tty= -p $$` in the claude pane) names your current session id. Re-running `bash deploy.sh claude` installs the hook; it takes effect on the *next* session start, not the current one.
- **Context % looks wrong / costs look off** — the panel infers the model ID from the live transcript to price each turn and size the context window correctly; if pricing changes on Anthropic's side, update the `PRICES` table inside `ccusage-panel.sh`.
- **"Value" figures don't match my actual bill** — expected on Pro/Max/Team plans. Every $ figure in the panel is `local token count × pay-as-you-go API rate`, not a real charge — it's a proxy for how much of the model you're using, not an invoice. Flat-rate subscribers will see numbers well above (or below) what they're actually billed.

## License

MIT
