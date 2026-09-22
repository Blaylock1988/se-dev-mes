#!/usr/bin/env pwsh
# run-mes-audit.ps1
# Shim: runs se-dev-mes skill audit scripts against this mod's Content/Data folder.
# Usage (from mod root):  .\run-mes-audit.ps1 [-Audit sbc|tags|refs|prefabs|unknown] [-Path <dir>]
param(
    [ValidateSet("sbc","tags","refs","prefabs","unknown","wc")]
    [string]$Audit = "sbc",
    [string]$Path  = ".\Content\Data"
)

$SkillRoot = "C:\Users\blayl\.gemini\config\skills\se-dev-mes"
$AbsPath   = Resolve-Path $Path -ErrorAction Stop

switch ($Audit) {
    "sbc"     { powershell -ExecutionPolicy Bypass -File "$SkillRoot\scripts\audit_sbc.ps1"           -Path $AbsPath }
    "tags"    { powershell -ExecutionPolicy Bypass -File "$SkillRoot\scripts\audit_mes_tags.ps1"       -Path $AbsPath }
    "refs"    { powershell -ExecutionPolicy Bypass -File "$SkillRoot\scripts\audit_mes_references.ps1" -Path $AbsPath -WarnOrphans -SkipPrefabs }
    "prefabs" { powershell -ExecutionPolicy Bypass -File "$SkillRoot\scripts\audit_prefabs.ps1"        -Path $AbsPath }
    "unknown" { uv run --project $SkillRoot "$SkillRoot\scripts\audit_unknown_tags.py" $AbsPath }
    "wc"      { uv run --project $SkillRoot "$SkillRoot\scripts\wc_shootmode.py" list $AbsPath }
}

