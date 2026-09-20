<#
.SYNOPSIS
    Cross-reference validator for MES and RivalAI profiles in Space Engineers SBC files.
.DESCRIPTION
    Scans all .sbc files in the target directory to:
    1. Collect all defined SubtypeIds across:
       - Triggers, TriggerGroups, Actions, Conditions, Spawners, Chats, Behaviors
       - SpawnGroups
       - Prefabs
       - MES Events, Event Actions, Event Conditions
       - Zones
    2. Collect all referenced SubtypeIds across:
       - Remote Control profiles: [Triggers], [TriggerGroups]
       - Trigger profiles: [Conditions], [Actions]
       - TriggerGroup profiles: [Triggers]
       - Action profiles: [Spawner], [SpawnData], [Chat], [ChatData], [CommandProfileIds], [ToggleEventIds]
       - Spawner profiles: [SpawnGroups]
       - SpawnGroup definitions: [SpawnConditionsProfiles], <Prefab SubtypeId="...">
       - Event profiles: [ConditionIds], [ActionIds]
    3. Cross-reference definitions and references to flag:
       - Missing / Dangling references (referenced but never defined)
       - Case mismatches (e.g. 'GVK-Action-Foo' vs 'GVK-Action-foo')
       - Orphaned definitions (defined but never referenced anywhere)
.PARAMETER Path
    Path to the mod's Data or Content directory. Defaults to current directory.
.PARAMETER IncludePrefabs
    Whether to scan prefabs for definitions. Defaults to true.
.PARAMETER WarnOrphans
    Whether to warn about unused/orphaned profiles. Defaults to false.
#>
param(
    [string]$Path = ".",
    [switch]$IncludePrefabs = $true,
    [switch]$WarnOrphans = $false
)

Write-Host "Scanning SBC files in: $Path" -ForegroundColor Cyan

# 1. Collect all .sbc files
$sbcFiles = Get-ChildItem -Path $Path -Filter *.sbc -Recurse
if ($sbcFiles.Count -eq 0) {
    Write-Host "No .sbc files found in $Path" -ForegroundColor Red
    exit 1
}

# Dictionaries to track definitions: Name -> @{ File = $file; Line = $line; ExactName = $name; Type = $type }
$definitions = @{}
$definitionsLower = @{}

# List of references: @{ Name = $name; File = $file; Line = $line; RefType = $refType }
$references = [System.Collections.Generic.List[PSObject]]::new()

function Register-Definition($name, $file, $line, $type) {
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $trimmed = $name.Trim()
    $lower = $trimmed.ToLowerInvariant()

    if ($definitions.ContainsKey($trimmed)) {
        # Duplicate definition warning
        Write-Host "[WARN] Duplicate definition of '$trimmed' in $($file.Name):$line (previously in $($definitions[$trimmed].File.Name):$($definitions[$trimmed].Line))" -ForegroundColor Yellow
    } else {
        $defObj = [PSCustomObject]@{
            File = $file
            Line = $line
            ExactName = $trimmed
            Type = $type
        }
        $definitions[$trimmed] = $defObj
        $definitionsLower[$lower] = $defObj
    }
}

function Register-Reference($names, $file, $line, $refType) {
    if ($null -eq $names) { return }
    foreach ($n in $names) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $trimmed = $n.Trim()
        if ($trimmed.Length -eq 0) { continue }
        $references.Add([PSCustomObject]@{
            Name = $trimmed
            File = $file
            Line = $line
            RefType = $refType
        })
    }
}

function Parse-CsvTags($block, $tagName) {
    if ($block -match "\[$tagName\s*:\s*([^\]]+)\]") {
        $val = $matches[1].Trim()
        return ($val -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
    }
    return @()
}

# Scan pass 1: Collect definitions and references
foreach ($file in $sbcFiles) {
    $isPrefab = $file.FullName -match '\\(Prefabs|StorePrefabs)(\\|$)'
    if ($isPrefab -and -not $IncludePrefabs) { continue }

    $content = [System.IO.File]::ReadAllText($file.FullName)
    $lines = $content -split "`r?`n"

    # XML-level definitions: <SubtypeId> or <Prefab Subtype="...">
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNum = $i + 1

        # Check <SubtypeId>Foo</SubtypeId>
        if ($line -match '<SubtypeId>([^<]+)</SubtypeId>') {
            $subId = $matches[1].Trim()
            Register-Definition $subId $file $lineNum "SubtypeId"
        }

        # Check <Id Type="..." Subtype="Foo" />
        if ($line -match '<Id\s+[^>]*Subtype="([^"]+)"') {
            $subId = $matches[1].Trim()
            Register-Definition $subId $file $lineNum "SubtypeAttr"
        }

        # Check Prefab references inside SpawnGroups: <Prefab SubtypeId="Foo">
        if ($line -match '<Prefab\s+[^>]*SubtypeId="([^"]+)"') {
            Register-Reference @($matches[1].Trim()) $file $lineNum "SpawnGroupPrefab"
        }
    }

    # Description profile block references
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '(?s)<Description>(.*?)</Description>')
    foreach ($dm in $descMatches) {
        $block = $dm.Groups[1].Value

        # Remote Control / Behavior references
        Register-Reference (Parse-CsvTags $block 'Triggers') $file 0 "Trigger"
        Register-Reference (Parse-CsvTags $block 'TriggerGroups') $file 0 "TriggerGroup"

        # Trigger references
        Register-Reference (Parse-CsvTags $block 'Conditions') $file 0 "Condition"
        Register-Reference (Parse-CsvTags $block 'Actions') $file 0 "Action"

        # Action references
        Register-Reference (Parse-CsvTags $block 'Spawner') $file 0 "Spawner"
        Register-Reference (Parse-CsvTags $block 'SpawnData') $file 0 "SpawnData"
        Register-Reference (Parse-CsvTags $block 'Chat') $file 0 "Chat"
        Register-Reference (Parse-CsvTags $block 'ChatData') $file 0 "ChatData"
        Register-Reference (Parse-CsvTags $block 'CommandProfileIds') $file 0 "CommandProfile"
        Register-Reference (Parse-CsvTags $block 'ToggleEventIds') $file 0 "ToggleEvent"
        Register-Reference (Parse-CsvTags $block 'ResetEventCooldownIds') $file 0 "ResetEvent"

        # Spawner references
        Register-Reference (Parse-CsvTags $block 'SpawnGroups') $file 0 "SpawnGroup"

        # SpawnGroup references
        Register-Reference (Parse-CsvTags $block 'SpawnConditionsProfiles') $file 0 "SpawnCondition"

        # Event references
        Register-Reference (Parse-CsvTags $block 'ConditionIds') $file 0 "EventCondition"
        Register-Reference (Parse-CsvTags $block 'ActionIds') $file 0 "EventAction"
    }
}

Write-Host "Total Definitions Indexed: $($definitions.Count)" -ForegroundColor Gray
Write-Host "Total References Checked: $($references.Count)" -ForegroundColor Gray
Write-Host ""

$errors = 0
$warnings = 0
$referencedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Pass 2: Validate all references
foreach ($ref in $references) {
    $refName = $ref.Name
    $referencedNames.Add($refName) | Out-Null
    $refLower = $refName.ToLowerInvariant()

    # Skip vanilla / external engine presets or common keywords if applicable
    if ($refName -in @("true", "false", "None", "Default")) { continue }

    if (-not $definitionsLower.ContainsKey($refLower)) {
        Write-Host "[ERROR] Missing Reference ($($ref.RefType)): '$refName' referenced in $($ref.File.Name) is not defined anywhere!" -ForegroundColor Red
        $errors++
    } elseif (-not $definitions.ContainsKey($refName)) {
        $actual = $definitionsLower[$refLower].ExactName
        Write-Host "[WARN] Case Mismatch ($($ref.RefType)): '$refName' in $($ref.File.Name) does not match definition '$actual' in $($definitionsLower[$refLower].File.Name)" -ForegroundColor Yellow
        $warnings++
    }
}

# Pass 3: Check for orphans (optional)
if ($WarnOrphans) {
    foreach ($defKey in $definitions.Keys) {
        if (-not $referencedNames.Contains($defKey)) {
            $def = $definitions[$defKey]
            # Ignore root objects that are naturally unreferenced like SpawnGroups or Prefabs
            if ($def.Type -eq "SubtypeId" -and $def.File.FullName -notmatch '\\(Prefabs|StorePrefabs)(\\|$)' -and $defKey -notmatch 'SpawnGroup') {
                Write-Host "[INFO] Potentially Unused Profile: '$defKey' in $($def.File.Name):$($def.Line)" -ForegroundColor DarkGray
            }
        }
    }
}

Write-Host ""
if ($errors -eq 0 -and $warnings -eq 0) {
    Write-Host "All profile cross-references verified successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Cross-Reference Audit Complete: $errors missing reference(s), $warnings case mismatch(es)." -ForegroundColor $(if ($errors -gt 0) { "Red" } else { "Yellow" })
    if ($errors -gt 0) { exit 1 }
}

