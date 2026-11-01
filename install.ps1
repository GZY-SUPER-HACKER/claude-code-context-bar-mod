param(
  [string]$DevModsRoot = (Join-Path $HOME ".claude\dev-mods"),
  [string]$SettingsPath = (Join-Path $HOME ".claude\settings.json"),
  [switch]$WriteSettings
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$uuid = [guid]::NewGuid().ToString()
$target = Join-Path $DevModsRoot "$uuid\context-bar"

Write-Host "Installing context-bar mod to:"
Write-Host "  $target"

New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Recurse -Force (Join-Path $repoRoot ".claude-plugin") $target
Copy-Item -Recurse -Force (Join-Path $repoRoot "hooks") $target

$escaped = $target.Replace('\', '\\')
$snippet = @"
Add this under "env" in $SettingsPath:

  "CLAUDE_CODE_PLUGIN_DIRS": "$escaped"

"@
Write-Host $snippet

if (-not $WriteSettings) {
  Write-Host "Settings not modified. Re-run with -WriteSettings to merge it automatically."
  Write-Host "Then run 'Developer: Reload Window' in VS Code."
  exit 0
}

if (-not (Test-Path $SettingsPath)) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SettingsPath) | Out-Null
  '{"env":{}}' | Set-Content -Path $SettingsPath -Encoding ascii
}

$backup = "$SettingsPath.bak-context-bar-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Copy-Item -Force $SettingsPath $backup
Write-Host "Backup: $backup"

$raw = Get-Content -Raw -Path $SettingsPath
$json = $raw | ConvertFrom-Json
if ($null -eq $json.env) {
  $json | Add-Member -MemberType NoteProperty -Name env -Value ([pscustomobject]@{}) -Force
}
$existing = $json.env.CLAUDE_CODE_PLUGIN_DIRS
if ($existing -and $existing -ne $target) {
  Write-Warning "Replacing existing CLAUDE_CODE_PLUGIN_DIRS: $existing"
}
$json.env | Add-Member -MemberType NoteProperty -Name CLAUDE_CODE_PLUGIN_DIRS -Value $target -Force

$out = $json | ConvertTo-Json -Depth 100
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($SettingsPath, $out, $utf8)

Write-Host "Updated $SettingsPath"
Write-Host "Now run 'Developer: Reload Window' in VS Code."
