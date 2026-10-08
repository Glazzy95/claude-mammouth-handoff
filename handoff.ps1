# Claude Code Stop / StopFailure hook.
# Writes <workspace>\HANDOFF.md (and a copy to handoff\latest.md) so another agent
# (OpenCode + Mammouth) can continue if Claude runs out of tokens.
# Runs locally from the transcript - costs no Claude tokens.
# The workspace is the folder that contains this handoff folder; sessions outside it are ignored.

$Root = Split-Path $PSScriptRoot -Parent
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [Text.Encoding]::UTF8
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Shorten([string]$s, [int]$max) {
    if (-not $s) { return '' }
    $s = $s.Trim()
    if ($s.Length -le $max) { return $s }
    return $s.Substring(0, $max) + ' ...[cut]'
}

function Get-TextBlocks($content) {
    if ($content -is [string]) { return @($content) }
    $out = @()
    foreach ($b in $content) { if ($b.type -eq 'text' -and $b.text) { $out += $b.text } }
    return $out
}

function Get-UserText($entry) {
    if ($entry.type -ne 'user' -or $entry.isMeta) { return $null }
    $parts = Get-TextBlocks $entry.message.content | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('<') }
    if (-not $parts) { return $null }
    return ($parts -join "`n")
}

function ConvertFrom-JsonLine([string]$line) {
    try { return $line | ConvertFrom-Json } catch { return $null }
}

$hook = [Console]::In.ReadToEnd() | ConvertFrom-Json
$transcript = $hook.transcript_path
$cwd = $hook.cwd
if (-not $transcript -or -not (Test-Path -LiteralPath $transcript) -or -not $cwd) { exit 0 }
$cwd = [IO.Path]::GetFullPath(($cwd -replace '/', '\')).TrimEnd('\')
if (-not (($cwd -ieq $Root) -or $cwd.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase))) { exit 0 }

$lines = [IO.File]::ReadAllLines($transcript, [Text.Encoding]::UTF8)

# How the session started: first 3 real user prompts.
$firstPrompts = @()
foreach ($line in $lines) {
    if ($firstPrompts.Count -ge 3) { break }
    if ($line -notmatch '"type":"user"') { continue }
    $t = Get-UserText (ConvertFrom-JsonLine $line)
    if ($t) { $firstPrompts += (Shorten $t 1200) }
}

# Recent activity: only parse the tail of the transcript (fast on big sessions).
$tail = if ($lines.Count -gt 600) { $lines[($lines.Count - 600)..($lines.Count - 1)] } else { $lines }
$recentPrompts = New-Object System.Collections.ArrayList
$actions = New-Object System.Collections.ArrayList
$lastReply = ''
foreach ($line in $tail) {
    $e = ConvertFrom-JsonLine $line
    if (-not $e) { continue }
    if ($e.type -eq 'user') {
        $t = Get-UserText $e
        if ($t) { [void]$recentPrompts.Add((Shorten $t 1500)); $lastReply = '' }
    }
    elseif ($e.type -eq 'assistant' -and $e.message.content -isnot [string]) {
        foreach ($b in $e.message.content) {
            if ($b.type -eq 'text' -and $b.text.Trim()) { $lastReply = $b.text }
            elseif ($b.type -eq 'tool_use') {
                $i = $b.input
                $desc = switch -Regex ($b.name) {
                    '^(Edit|Write|NotebookEdit|Read)$' { "$($b.name) $($i.file_path)" }
                    '^(Bash|PowerShell)$' { "$($b.name): " + $(if ($i.description) { $i.description } else { Shorten $i.command 150 }) }
                    default { $b.name }
                }
                [void]$actions.Add($desc)
            }
        }
    }
}

# Files changed in the whole session.
$files = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches(($lines -join "`n"), '"name":"(?:Edit|Write|NotebookEdit)","input":\{"file_path":"((?:[^"\\]|\\.)*)"')) {
    $p = $m.Groups[1].Value -replace '\\\\', '\'
    if (-not $files.Contains($p)) { $files.Add($p) }
}

$failed = $hook.hook_event_name -eq 'StopFailure'
$status = if ($failed) { 'STOPPED UNEXPECTEDLY (usage limit or error) - the last step may be unfinished' } else { 'Claude finished its last reply normally' }
$recent = @($recentPrompts | Select-Object -Last 5)
$lastActions = @($actions | Select-Object -Last 12)

$memDir = Join-Path $Root '.claude-memory\MEMORY.md'

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# HANDOFF - continue this work')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("Written by: **Claude Code** (auto hook), $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Status: **$status**.")
[void]$sb.AppendLine("Project folder: ``$cwd``")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## How to continue')
[void]$sb.AppendLine('- The **last user request** below is the current task. Check its state in the files before changing anything.')
[void]$sb.AppendLine("- If Claude's last reply ends mid-task or the status says STOPPED, finish that step first.")
[void]$sb.AppendLine('- Read CLAUDE.md / README.md in the project if they exist.')
if (Test-Path -LiteralPath $memDir) { [void]$sb.AppendLine("- Claude's long-term notes for this folder: ``$memDir`` (and the files it links to).") }
[void]$sb.AppendLine('- Answer in the language the user writes in.')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## How the session started')
foreach ($p in $firstPrompts) { [void]$sb.AppendLine("> $($p -replace "`n", "`n> ")"); [void]$sb.AppendLine('') }
[void]$sb.AppendLine('## Latest user requests (oldest first, last one = current task)')
$n = 1
foreach ($p in $recent) { [void]$sb.AppendLine("$n. $($p -replace "`n", "`n   ")"); $n++ }
[void]$sb.AppendLine('')
[void]$sb.AppendLine("## Claude's last reply")
[void]$sb.AppendLine($(if ($lastReply) { Shorten $lastReply 5000 } else { '_(none after the last request - Claude was still working when it stopped)_' }))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Last actions (most recent last)')
foreach ($a in $lastActions) { [void]$sb.AppendLine("- $a") }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Files changed in this session')
if ($files.Count) { foreach ($f in $files) { [void]$sb.AppendLine("- ``$f``") } } else { [void]$sb.AppendLine('_(none)_') }

$text = $sb.ToString()
[IO.File]::WriteAllText((Join-Path $Root 'HANDOFF.md'), $text, $utf8)
[IO.File]::WriteAllText((Join-Path $Root 'handoff\latest.md'), $text, $utf8)
exit 0
