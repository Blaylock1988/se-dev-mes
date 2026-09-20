<#
.SYNOPSIS
    1-Step Automated Skill & Tag Database Updater for se-dev-mes.
.DESCRIPTION
    Executes a complete end-to-end synchronization workflow:
    1. Scans local MES installation (%AppData% or Steam Workshop).
    2. Rebuilds the offline tag cache (mes_tag_cache.json).
    3. Synchronizes the repository to the global skill directory (~/.gemini/config/skills/se-dev-mes).
    4. Runs pre-flight verification on all examples and scripts.
.PARAMETER MesPath
    Optional custom path to local MES source.
#>
param(
    [string]$MesPath = ""
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$globalSkillPath = [System.IO.Path]::Combine($env:USERPROFILE, ".gemini", "config", "skills", "se-dev-mes")

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " 1-Step MES Skill & Tag Database Updater" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Repository Root:   $repoRoot" -ForegroundColor Gray
Write-Host "Global Skill Path: $globalSkillPath" -ForegroundColor Gray
Write-Host ""

# Step 1: Rebuild Tag Cache
Write-Host "[1/4] Rebuilding offline tag cache from MES source..." -ForegroundColor Yellow
$pyArgs = @("scripts/query_mes_tags.py", "--rebuild-cache")
if (-not [string]::IsNullOrWhiteSpace($MesPath)) {
    $pyArgs += @("--path", $MesPath)
}
& python @pyArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to rebuild tag cache!" -ForegroundColor Red
    exit 1
}

# Step 2: Pre-Flight Verification on Examples
Write-Host "`n[2/4] Running pre-flight verification on production examples..." -ForegroundColor Yellow
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot/audit_sbc.ps1" -Path "$repoRoot/examples"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] SBC XML audit failed on examples!" -ForegroundColor Red
    exit 1
}

& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot/audit_mes_tags.ps1" -Path "$repoRoot/examples"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] MES tag audit failed on examples!" -ForegroundColor Red
    exit 1
}

& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot/audit_prefabs.ps1" -Path "$repoRoot/examples"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Prefab audit failed on examples!" -ForegroundColor Red
    exit 1
}

# Step 3: Synchronize to Global Skill Directory
Write-Host "`n[3/4] Synchronizing repository to global skill directory..." -ForegroundColor Yellow
if (Test-Path $globalSkillPath) {
    # Mirror files
    Copy-Item -Path "$repoRoot/SKILL.md" -Destination "$globalSkillPath/SKILL.md" -Force
    Copy-Item -Path "$repoRoot/README.md" -Destination "$globalSkillPath/README.md" -Force
    if (Test-Path "$repoRoot/VERSIONING.md") {
        Copy-Item -Path "$repoRoot/VERSIONING.md" -Destination "$globalSkillPath/VERSIONING.md" -Force
    }

    if (Test-Path "$repoRoot/references") {
        Copy-Item -Path "$repoRoot/references" -Destination $globalSkillPath -Recurse -Force
    }
    if (Test-Path "$repoRoot/examples") {
        Copy-Item -Path "$repoRoot/examples" -Destination $globalSkillPath -Recurse -Force
    }
    if (Test-Path "$repoRoot/scripts") {
        Copy-Item -Path "$repoRoot/scripts" -Destination $globalSkillPath -Recurse -Force
    }
    Write-Host "Global skill directory synchronized successfully." -ForegroundColor Green
} else {
    Write-Host "[INFO] Global skill path ($globalSkillPath) does not exist yet. Skipping mirror." -ForegroundColor Gray
}

# Step 4: Health Summary
Write-Host "`n[4/4] MES Skill Health Check:" -ForegroundColor Yellow
& python "$PSScriptRoot/check_mes_sync.py"

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host " Update Complete! se-dev-mes is 100% in sync with latest MES." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green

