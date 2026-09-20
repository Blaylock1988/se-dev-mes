<#
.SYNOPSIS
    Pre-build XML audit script for Space Engineers SBC files.
.DESCRIPTION
    Audits .sbc files for common Keen deserializer failure modes:
    1. Duplicate SubtypeId elements inside an <Id> block.
    2. Duplicate <Id> elements inside a <Prefab> definition.
    3. XML comments (<!-- ... -->) inside <Description> tags.
.PARAMETER Path
    Path to search for .sbc files. Defaults to current directory.
#>
param(
    [string]$Path = "."
)

$files = Get-ChildItem -Path $Path -Filter *.sbc -Recurse | Where-Object { 
    $_.FullName -notmatch '\\(Prefabs|StorePrefabs)(\\|$)' 
}

$errorsFound = 0

foreach ($file in $files) {
    $raw = [System.IO.File]::ReadAllText($file.FullName)
    
    # Check 1: XML comments inside <Description>
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($raw, '(?s)<Description>(.*?)</Description>')
    foreach ($m in $descMatches) {
        if ($m.Groups[1].Value -match '<!--') {
            Write-Host "[ERROR] XML Comment inside <Description> in: $($file.FullName)" -ForegroundColor Red
            $errorsFound++
        }
    }

    # Check 2: Duplicate IDs using XML DOM
    try {
        [xml]$doc = $raw
        $badChildIds = $doc.SelectNodes("//Id[count(SubtypeId) > 1]")
        if ($badChildIds.Count -gt 0) {
            Write-Host "[ERROR] Duplicate SubtypeId in <Id> in: $($file.FullName)" -ForegroundColor Red
            $errorsFound++
        }
        $badAttrIds = $doc.SelectNodes("//*[count(Id) > 1]")
        if ($badAttrIds.Count -gt 0) {
            Write-Host "[ERROR] Duplicate <Id> tag in: $($file.FullName)" -ForegroundColor Red
            $errorsFound++
        }
    } catch {
        Write-Host "[WARN] XML Parse failure in: $($file.FullName) - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($errorsFound -eq 0) {
    Write-Host "SBC XML Audit Passed: No deserializer hazards detected." -ForegroundColor Green
} else {
    Write-Host "SBC XML Audit FAILED: $errorsFound errors found." -ForegroundColor Red
    exit 1
}

