# Claude Code PreToolUse hook (optional): keeps Claude inside the workspace folder.
# The workspace is the folder that contains this handoff folder.
# Denies reading, searching, editing and shell commands that point outside $Root.
# Fails closed: if anything goes wrong, the tool call is denied.

$Root = Split-Path $PSScriptRoot -Parent

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Deny([string]$reason) {
    $out = @{ hookSpecificOutput = @{
        hookEventName = 'PreToolUse'
        permissionDecision = 'deny'
        permissionDecisionReason = "Blocked: $reason Only $Root may be read or changed (user rule)."
    } }
    [Console]::Out.Write(($out | ConvertTo-Json -Compress -Depth 5))
    exit 0
}

function Normalize([string]$p, [string]$base) {
    $p = $p.Trim().Trim('"', "'")
    if ($p -match '^/([a-zA-Z])(/|$)') { $p = $Matches[1] + ':\' + $p.Substring(3) }
    $p = $p -replace '^~(?=[\\/]|$)', $env:USERPROFILE
    $p = $p -replace '(?i)^(\$HOME|\$env:USERPROFILE|%USERPROFILE%)', $env:USERPROFILE
    $p = $p -replace '/', '\'
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $base $p }
    return [IO.Path]::GetFullPath($p).TrimEnd('\')
}

function Inside([string]$full) {
    $r = $Root.TrimEnd('\')
    return ($full -ieq $r) -or $full.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)
}

try {
    $hook = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $tool = [string]$hook.tool_name
    $in = $hook.tool_input
    $cwd = if ($hook.cwd) { [string]$hook.cwd } else { $Root }

    switch -Regex ($tool) {
        '^(Read|Edit|Write|NotebookEdit)$' {
            $p = if ($in.file_path) { $in.file_path } else { $in.notebook_path }
            if (-not $p) { Deny "$tool without a path." }
            if (-not (Inside (Normalize $p $cwd))) { Deny "$tool on '$p'." }
        }
        '^(Glob|Grep)$' {
            $p = if ($in.path) { $in.path } else { $cwd }
            if (-not (Inside (Normalize $p $cwd))) { Deny "$tool in '$p'." }
            if ($in.pattern -and $tool -eq 'Glob' -and ($in.pattern -match '\.\.|^[a-zA-Z]:|^/|^~')) { Deny "Glob pattern '$($in.pattern)' leaves the folder." }
        }
        '^(Bash|PowerShell)$' {
            $cmd = [string]$in.command
            $effCwd = $cwd
            # Allow a leading "cd <path inside the workspace>" to enter the folder.
            if ($cmd -match '^\s*(?:cd|Set-Location)\s+("([^"]+)"|''([^'']+)''|(\S+))\s*(&&|;|$)') {
                $target = @($Matches[2], $Matches[3], $Matches[4]) | Where-Object { $_ } | Select-Object -First 1
                $full = Normalize $target $cwd
                if (-not (Inside $full)) { Deny "cd to '$target'." }
                $effCwd = $full
            }
            if (-not (Inside (Normalize $effCwd $Root))) { Deny "shell command while the working directory ('$effCwd') is outside the folder. Start with: cd `"$Root`"" }
            if ($cmd -match '(?i)\$env:(APPDATA|LOCALAPPDATA|TEMP|TMP|ProgramFiles|windir|SystemRoot)|%(APPDATA|LOCALAPPDATA|TEMP|TMP|ProgramFiles|windir|SystemRoot)%|\$(TMPDIR|TEMP|TMP)\b|(^|[\s"''=])/(tmp|etc|usr|var|home|mnt|proc|dev/(?!null))') { Deny 'shell command uses a location outside the folder.' }
            $tokens = [regex]::Matches($cmd, '(?i)(?<![\w/.\\])(?:[a-z]:[\\/]|/[a-z]/|~[\\/]|\$HOME|\$env:USERPROFILE|%USERPROFILE%|\.\.(?:[\\/]|(?=[\s"'';&|)]|$)))[^\s"''|;&<>()]*')
            foreach ($t in $tokens) {
                $v = $t.Value
                if (-not (Inside (Normalize $v $effCwd))) { Deny "shell command touches '$v'." }
            }
        }
    }
    exit 0
}
catch {
    Deny "guard error ($($_.Exception.Message))."
}
