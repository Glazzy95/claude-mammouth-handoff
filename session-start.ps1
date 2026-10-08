# Claude Code SessionStart hook (startup, resume, clear, compact).
# If the last HANDOFF.md was written by Mammouth/OpenCode, hand it to Claude as context,
# so Claude continues from Mammouth's state instead of relying on a CLAUDE.md instruction.
# Does nothing when Claude itself wrote the last handoff, or outside the workspace.

$Root = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8

try {
    $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $cwd = if ($hook.cwd) { [IO.Path]::GetFullPath(([string]$hook.cwd -replace '/', '\')).TrimEnd('\') } else { '' }
    if (-not (($cwd -ieq $Root) -or $cwd.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase))) { exit 0 }

    $path = Join-Path $Root 'HANDOFF.md'
    if (-not (Test-Path -LiteralPath $path)) { exit 0 }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($text -notmatch 'Written by: \*\*Mammouth') { exit 0 }

    $context = "The user worked with Mammouth (OpenCode) since your last session, probably because Claude ran out of tokens. " +
        "Below is the handoff Mammouth's plugin wrote. Take it into account and continue from this state; " +
        "briefly tell the user you picked up Mammouth's work.`n`n" + $text
    $out = @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $context } }
    [Console]::Out.Write(($out | ConvertTo-Json -Compress -Depth 5))
}
catch {
    # Never block a session start; just skip the context.
}
exit 0
