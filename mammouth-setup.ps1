# One-time setup: store the Mammouth API key, point OpenCode at this folder's config, load the model list.
# Run in PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\handoff\mammouth-setup.ps1
# Re-run any time to refresh the model list (and to regenerate AGENTS.md from AGENTS.template.md).

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$workspace = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $PSScriptRoot 'opencode.json'
$agentsPath = Join-Path $PSScriptRoot 'AGENTS.md'

# Generate the personal files from the templates (they are git-ignored).
$agents = (Get-Content (Join-Path $PSScriptRoot 'AGENTS.template.md') -Raw).Replace('{{WORKSPACE}}', $workspace)
[IO.File]::WriteAllText($agentsPath, $agents, $utf8)
if (-not (Test-Path $configPath)) {
    $template = (Get-Content (Join-Path $PSScriptRoot 'opencode.template.json') -Raw).Replace('{{AGENTS_PATH}}', ($agentsPath -replace '\\', '/'))
    [IO.File]::WriteAllText($configPath, $template, $utf8)
}

# OpenCode reads its config from here instead of ~/.config/opencode.
[Environment]::SetEnvironmentVariable('OPENCODE_CONFIG', $configPath, 'User')
# Plugins (the handoff writer) load from this folder.
[Environment]::SetEnvironmentVariable('OPENCODE_CONFIG_DIR', (Join-Path $PSScriptRoot 'opencode-dir'), 'User')

$key = [Environment]::GetEnvironmentVariable('MAMMOUTH_API_KEY', 'User')
if (-not $key) {
    $secure = Read-Host 'Paste your Mammouth API key (mammouth.ai > Settings > API keys)' -AsSecureString
    $key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
    if (-not $key) { throw 'No key entered.' }
    [Environment]::SetEnvironmentVariable('MAMMOUTH_API_KEY', $key, 'User')
    Write-Host 'Key saved as user environment variable MAMMOUTH_API_KEY.'
}

$resp = Invoke-RestMethod -Uri 'https://api.mammouth.ai/v1/models' -Headers @{ Authorization = "Bearer $key" }
$ids = @($resp.data | ForEach-Object { $_.id } | Sort-Object)
if (-not $ids) { throw 'Mammouth returned no models - check the key and your API credits.' }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$models = New-Object PSObject
foreach ($id in $ids) { $models | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{ name = $id }) }
$config.provider.mammouth.models = $models

# Default model: prefer a Claude Sonnet, then any Claude, then the first one.
$default = ($ids | Where-Object { $_ -match 'sonnet' } | Select-Object -Last 1)
if (-not $default) { $default = ($ids | Where-Object { $_ -match 'claude' } | Select-Object -Last 1) }
if (-not $default) { $default = $ids[0] }
$config | Add-Member -NotePropertyName model -NotePropertyValue "mammouth/$default" -Force

$json = $config | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($configPath, $json, $utf8)

Write-Host "`n$($ids.Count) Mammouth models added to OpenCode. Default: mammouth/$default"
Write-Host 'Switch models inside OpenCode with /models.'
Write-Host 'Open a NEW terminal before running opencode, so it sees the key and config.'
