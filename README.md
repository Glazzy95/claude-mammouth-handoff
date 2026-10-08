# Claude Code ⇄ Mammouth handoff

> [!WARNING]
> **Hobby project. Read this before installing.**
> - **Unofficial.** Not affiliated with or endorsed by Anthropic, Mammouth or OpenCode.
> - **Barely tested.** It has run on one Windows PC with OpenCode 1.18. Other setups may break, and later
>   OpenCode versions may change the plugin API. No support is promised.
> - **The guard is not a security boundary.** It only checks Claude Code's tool calls, and shell commands
>   only heuristically, so it can be bypassed. OpenCode is not restricted by it at all.
> - **Your conversation leaves your PC.** `HANDOFF.md` contains chat text, paths and possibly file contents
>   or anything you pasted, including secrets. In Mammouth sessions this goes to Mammouth and the model
>   provider behind it. Don't use it with code or data you're not allowed to share, such as an employer's.
> - **It changes your setup.** The installer edits `~/.claude/settings.json` (a backup is made), and the
>   setup script stores your API key in a Windows user environment variable. See [Uninstall](#uninstall).

Keep working when Claude Code runs out of tokens. This switches you to
[OpenCode](https://opencode.ai) running on a [Mammouth](https://mammouth.ai) API key, and back again,
without losing track of the task.

After every reply, whichever assistant just worked rewrites one shared file, `HANDOFF.md`. It holds the
current task, the last reply, recent actions and changed files. The other assistant reads it first and
continues from there.

```
 Claude Code ──(Stop hook)──────────┐                ┌──(plugin, session.idle)── OpenCode + Mammouth
                                    ▼                ▼
                          <workspace>\HANDOFF.md  "Written by: …"
                                    │                │
 Claude Code gets it ◄─ SessionStart┘                └─ AGENTS.md ─► OpenCode reads it
                        hook (if written by Mammouth)
```

- **No tokens spent on bookkeeping.** The handoff is built locally from the session transcript and
  history, not written by the model.
- **Works when Claude is cut off.** The `StopFailure` hook also fires when a reply is interrupted by a
  usage limit.
- **Claude can't miss Mammouth's work.** When a Claude Code session starts or resumes (CLI, VS Code or
  desktop app) and the last handoff came from Mammouth, a `SessionStart` hook injects it into Claude's context.
- **Optional guard.** It tries to stop Claude Code from reading or changing files outside the workspace
  folder. It's a safety net against mistakes, not protection against a determined bypass (see the warning above).

> Windows only (PowerShell 5.1+). Tested with Claude Code and OpenCode 1.18.

## Layout

Put this folder **inside your workspace**, the folder you work in with Claude Code. The workspace is
always the parent of this folder:

```
MyWorkspace\
├─ HANDOFF.md            ← written here automatically
├─ CLAUDE.md             ← your project rules (add the snippet below)
├─ some-project\
└─ handoff\              ← this repository
   ├─ handoff.ps1        Claude Code Stop/StopFailure hook → HANDOFF.md
   ├─ session-start.ps1  Claude Code SessionStart hook: feeds Mammouth's handoff to Claude
   ├─ guard.ps1          optional PreToolUse hook: stay inside the workspace
   ├─ install-claude-hooks.ps1
   ├─ mammouth-setup.ps1 key, model list, OpenCode config
   ├─ mammouth.cmd       starts OpenCode in the workspace
   ├─ AGENTS.template.md instructions for the OpenCode model
   ├─ opencode.template.json
   └─ opencode-dir\plugins\handoff.js   OpenCode plugin → HANDOFF.md
```

## Setup

Requirements: [Claude Code](https://claude.com/claude-code),
[Node.js](https://nodejs.org) and a Mammouth API key with credits. The API is billed separately from the
Mammouth app subscription.

```powershell
cd C:\path\to\MyWorkspace
git clone https://github.com/Glazzy95/claude-mammouth-handoff.git handoff

# 1. OpenCode
npm i -g opencode-ai

# 2. Claude Code hooks (add -Guard to keep Claude inside the workspace)
powershell -ExecutionPolicy Bypass -File .\handoff\install-claude-hooks.ps1

# 3. Mammouth key + model list + OpenCode config (asks for the key once)
powershell -ExecutionPolicy Bypass -File .\handoff\mammouth-setup.ps1
```

Restart Claude Code and open a **new** terminal, so the hooks and environment variables load.

## Usage

- **Claude runs out of tokens:** run `handoff\mammouth.cmd` and say *"continue"*.
- **Back to Claude:** start or resume a session in the workspace. Claude receives Mammouth's handoff
  automatically and says that it picked up Mammouth's work.
- Switch models in OpenCode with `/models`. Re-run `mammouth-setup.ps1` to refresh the list.

`mammouth-setup.ps1` sets three user environment variables: `MAMMOUTH_API_KEY`, `OPENCODE_CONFIG` and
`OPENCODE_CONFIG_DIR`. Edit `AGENTS.template.md` to change OpenCode's instructions, then re-run the setup.

## Good to know

- **`HANDOFF.md` contains your conversation text.** Anything you paste into a chat ends up there. If your
  workspace is a git repo, add `HANDOFF.md` to its `.gitignore`.
- **The guard is a safety net, not a sandbox.** File tools are checked exactly. Shell commands are
  checked heuristically, by looking for paths, `..`, `$HOME`, `%APPDATA%` and similar. It fails closed:
  errors deny the call.
- **OpenCode follows the workspace rule only through its instructions.** It isn't technically restricted,
  and OpenCode keeps its own data in your user profile.
- **Running with `opencode` instead of `opencode.cmd` fails** if PowerShell script execution is disabled.
  `mammouth.cmd` avoids that.
- The plugin writes `handoff\plugin-debug.log`, plus `plugin-error.txt` if something fails.

## Uninstall

Remove the `handoff.ps1` / `session-start.ps1` / `guard.ps1` entries from `~/.claude/settings.json` (a backup is in
`settings.json.bak`). Delete the environment variables `OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR` and
`MAMMOUTH_API_KEY`. Then delete this folder.

## License

MIT
