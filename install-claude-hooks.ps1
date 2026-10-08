# Registers the handoff hooks in your Claude Code user settings (~/.claude/settings.json).
#   powershell -ExecutionPolicy Bypass -File .\handoff\install-claude-hooks.ps1          # handoff only
#   powershell -ExecutionPolicy Bypass -File .\handoff\install-claude-hooks.ps1 -Guard   # + keep Claude inside the workspace
# Safe to re-run: earlier entries of these hooks are replaced, everything else is kept.
# A backup is written to settings.json.bak first.

param(
    [switch]$Guard,
    [string]$SettingsPath = (Join-Path $HOME '.claude\settings.json')
)

$ErrorActionPreference = 'Stop'
$settingsPath = $SettingsPath
$here = $PSScriptRoot -replace '\\', '/'

function New-HookEntry([string]$script, [bool]$async, [string]$matcher) {
    $hook = [ordered]@{
        type    = 'command'
        command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$here/$script`""
        timeout = 30
    }
    if ($async) { $hook.async = $true }
    $entry = [ordered]@{ hooks = @([pscustomobject]$hook) }
    if ($matcher) { $entry = [ordered]@{ matcher = $matcher; hooks = $entry.hooks } }
    return [pscustomobject]$entry
}

# Keep entries that are not ours, then add ours.
function Set-HookEvent($hooks, [string]$eventName, $entry) {
    $kept = @()
    if ($hooks.PSObject.Properties[$eventName]) {
        $kept = @($hooks.$eventName | Where-Object { -not ($_.hooks | Where-Object { $_.command -match 'handoff\.ps1|guard\.ps1|session-start\.ps1' }) })
    }
    $value = @($kept)
    if ($entry) { $value += $entry }
    if ($value.Count) { $hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue $value -Force }
    elseif ($hooks.PSObject.Properties[$eventName]) { $hooks.PSObject.Properties.Remove($eventName) }
}

if (Test-Path $settingsPath) {
    Copy-Item $settingsPath "$settingsPath.bak" -Force
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    New-Item -ItemType Directory -Force (Split-Path $settingsPath) | Out-Null
    $settings = [pscustomobject]@{}
}
if (-not $settings.PSObject.Properties['hooks']) { $settings | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }

Set-HookEvent $settings.hooks 'Stop' (New-HookEntry 'handoff.ps1' $true $null)
Set-HookEvent $settings.hooks 'StopFailure' (New-HookEntry 'handoff.ps1' $true $null)
Set-HookEvent $settings.hooks 'SessionStart' (New-HookEntry 'session-start.ps1' $false $null)
$guardEntry = if ($Guard) { New-HookEntry 'guard.ps1' $false 'Read|Edit|Write|NotebookEdit|Glob|Grep|Bash|PowerShell' } else { $null }
Set-HookEvent $settings.hooks 'PreToolUse' $guardEntry

$json = $settings | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Hooks installed in $settingsPath (backup: settings.json.bak)."
Write-Host "Workspace: $(Split-Path $PSScriptRoot -Parent)"
if ($Guard) { Write-Host 'Guard enabled: Claude can no longer read or change files outside the workspace.' }
Write-Host 'Restart Claude Code (or open /hooks once) to load the hooks.'
