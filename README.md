# Claude Code ⇄ Mammouth handoff

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
 Claude Code reads it ◄─ CLAUDE.md ─┘                └─ AGENTS.md ─► OpenCode reads it
```

- **No tokens spent on bookkeeping.** The handoff is built locally from the session transcript and
  history, not written by the model.
- **Works when Claude is cut off.** The `StopFailure` hook also fires when a reply is interrupted by a
  usage limit.
- **Optional guard.** It blocks Claude Code from reading or changing anything outside the workspace folder.

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

Then add this to `MyWorkspace\CLAUDE.md`, so Claude picks up what Mammouth did:

```markdown
- At the start of a session, read `HANDOFF.md` in this folder before replying. If it says
  "Written by: Mammouth", continue from Mammouth's state.
```

Restart Claude Code and open a **new** terminal, so the hooks and environment variables load.

## Usage

- **Claude runs out of tokens:** run `handoff\mammouth.cmd` and say *"continue"*.
- **Back to Claude:** just keep going. Claude reads `HANDOFF.md` first.
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

Remove the `handoff.ps1` / `guard.ps1` entries from `~/.claude/settings.json` (a backup is in
`settings.json.bak`). Delete the environment variables `OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR` and
`MAMMOUTH_API_KEY`. Then delete this folder.

## License

MIT
