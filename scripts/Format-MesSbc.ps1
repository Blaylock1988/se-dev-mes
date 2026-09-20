<#
.SYNOPSIS
    Safe SBC XML Formatter & Auto-Cleaner for Space Engineers MES profiles.
.DESCRIPTION
    Formats SBC XML indentation cleanly while strictly isolating and protecting
    <Description> blocks from text wrapping or whitespace mangling.
    
    Automatically fixes Keen deserializer hazards:
    1. Converts illegal XML comments (<!-- ... -->) inside <Description> into safe RivalAI comments ([//...]).
    2. Normalizes UTF-8 encoding.
.PARAMETER Path
    Path to a specific .sbc file or directory of .sbc files.
.PARAMETER DryRun
    If true, reports what would be changed without modifying files on disk.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    [switch]$DryRun = $false
)

$targetFiles = @()
if (Test-Path -Path $Path -PathType Leaf) {
    $targetFiles += (Get-Item $Path)
} elseif (Test-Path -Path $Path -PathType Container) {
    $targetFiles += (Get-ChildItem -Path $Path -Filter *.sbc -Recurse | Where-Object { 
        $_.FullName -notmatch '\\(Prefabs|StorePrefabs)(\\|$)' 
    })
} else {
    Write-Host "[ERROR] Path not found: $Path" -ForegroundColor Red
    exit 1
}

$filesModified = 0

foreach ($file in $targetFiles) {
    $raw = [System.IO.File]::ReadAllText($file.FullName)
    $descriptions = @{}
    $placeholderIndex = 0

    # 1. Extract and protect <Description> blocks, auto-converting illegal XML comments
    $protected = [System.Text.RegularExpressions.Regex]::Replace($raw, '(?s)<Description>(.*?)</Description>', {
        param($match)
        $inner = $match.Groups[1].Value

        # Auto-convert XML comments inside description to RivalAI comments
        if ($inner -match '<!--') {
            $inner = [System.Text.RegularExpressions.Regex]::Replace($inner, '<!--\s*(.*?)\s*-->', {
                param($cm)
                return "[//" + $cm.Groups[1].Value + "]"
            })
            Write-Host "[AUTO-FIX] Converted illegal XML comment in $($file.Name)" -ForegroundColor Yellow
        }

        $token = "__MES_DESC_PLACEHOLDER_${placeholderIndex}__"
        $descriptions[$token] = "<Description>$inner</Description>"
        $placeholderIndex++
        return $token
    })

    # 2. Format the outer XML structure
    try {
        $xmlDoc = [System.Xml.Linq.XDocument]::Parse($protected)
        $settings = [System.Xml.XmlWriterSettings]::new()
        $settings.Indent = $true
        $settings.IndentChars = "  "
        $settings.OmitXmlDeclaration = $false
        $settings.Encoding = [System.Text.Encoding]::UTF8

        $sb = [System.Text.StringBuilder]::new()
        $writer = [System.Xml.XmlWriter]::Create($sb, $settings)
        $xmlDoc.Save($writer)
        $writer.Dispose()
        $formatted = $sb.ToString()

        # 3. Restore protected <Description> blocks
        foreach ($token in $descriptions.Keys) {
            $formatted = $formatted.Replace($token, $descriptions[$token])
        }

        # Check if content changed
        if ($raw -ne $formatted) {
            if (-not $DryRun) {
                [System.IO.File]::WriteAllText($file.FullName, $formatted, [System.Text.Encoding]::UTF8)
                Write-Host "[FORMATTED] $($file.Name)" -ForegroundColor Green
            } else {
                Write-Host "[WOULD FORMAT] $($file.Name)" -ForegroundColor Cyan
            }
            $filesModified++
        }
    } catch {
        Write-Host "[WARN] Could not parse $($file.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "`nFormat pass complete. $filesModified file(s) updated." -ForegroundColor $(if ($filesModified -gt 0) { "Green" } else { "Gray" })

