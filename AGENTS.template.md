# Instructions for OpenCode + Mammouth

The user mainly works with Claude Code and switches to you when Claude runs out of tokens.

## Hard rule: stay inside the workspace
- Only read, search, create, edit or delete files inside `{{WORKSPACE}}`.
- Everything else on this computer is off limits, including reading. Don't run commands that touch other locations.
  If a task seems to need something outside, stop and ask the user.

## Continuing Claude's work
- **At the start of every session**, read `{{WORKSPACE}}\HANDOFF.md` first.
  It is rewritten automatically after every reply (by Claude Code or by you). It describes the current task,
  the last reply, recent actions, changed files and the project folder. Continue from there instead of starting over.
- Also follow `CLAUDE.md` in the project if present. Those are the project rules Claude used.
- Do not delete or rewrite `HANDOFF.md` yourself.

## Handing back to Claude
- A plugin rewrites `HANDOFF.md` automatically after each of your replies, so Claude can continue from your state.
  You don't need to write it yourself.
- The file's "Written by" line shows who worked last. If it says Mammouth, it's your own earlier session.
- Reply in the language the user writes in.
