<#
.SYNOPSIS
    Pre-build XML audit script for Space Engineers SBC files.
.DESCRIPTION
    Audits .sbc files for common Keen deserializer failure modes:
    1. XML comments (<!-- ... -->) inside <Description> tags (crashes ReadElementString with XmlException).
    2. Duplicate SubtypeId elements inside an <Id> block (silently drops subsequent IDs).
    3. Duplicate <Id> elements inside a <Prefab> definition.
    4. Empty or whitespace-only SubtypeId elements.
    5. Malformed XML syntax or missing closing tags.
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
    $lines = $raw -split "`r?`n"
    
    # Check 1: XML comments inside <Description>
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($raw, '(?s)<Description>(.*?)</Description>')
    foreach ($m in $descMatches) {
        if ($m.Groups[1].Value -match '<!--') {
            # Find approximate line number
            $preceding = $raw.Substring(0, $m.Index)
            $lineNo = ($preceding -split "`r?`n").Count
            Write-Host "[ERROR] $($file.Name):$lineNo - Fatal XML comment inside <Description>! Use [//Comment] syntax." -ForegroundColor Red
            $errorsFound++
        }
    }

    # Check 2: Empty or whitespace-only SubtypeId
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '<SubtypeId>\s*</SubtypeId>' -or $lines[$i] -match '<SubtypeId\s*/>') {
            $lineNo = $i + 1
            Write-Host "[ERROR] $($file.Name):$lineNo - Empty <SubtypeId> element detected!" -ForegroundColor Red
            $errorsFound++
        }
    }

    # Check 3: Duplicate IDs using XML DOM
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
        Write-Host "[ERROR] Malformed XML in: $($file.FullName) - $($_.Exception.Message)" -ForegroundColor Red
        $errorsFound++
    }
}

Write-Host ""
if ($errorsFound -eq 0) {
    Write-Host "SBC XML Audit Passed: No deserializer hazards detected." -ForegroundColor Green
    exit 0
} else {
    Write-Host "SBC XML Audit FAILED: $errorsFound error(s) found." -ForegroundColor Red
    exit 1
}
