<#
.SYNOPSIS
    Advanced audit script for MES and RivalAI tag pitfalls, master gates, and list alignments.
.DESCRIPTION
    Scans .sbc files for:
    1. Zero in CustomCountersTargets (zero-stripping bug).
    2. WaypointNear/WaypointFar trigger types (fatal bounds check crash).
    3. ChangeBlocksShareModeAll (broken loop index).
    4. [CutVoxels:true] on SpawnConditions (does not exist in MES).
    5. RivalAI vs MES Event Action tag mismatches ([Spawner:] vs [SpawnData:]).
    6. Missing boolean master gates in MES Event Actions and Conditions.
    7. List count mismatches on paired tags (SetCounters vs SetCountersAmount, etc.).
    8. Invalid token usage (e.g. {Faction} inside MES Event Actions, tokens in [Actions:] profile names).
.PARAMETER Path
    Path to search for .sbc files. Defaults to current directory.
#>
param(
    [string]$Path = "."
)

$files = Get-ChildItem -Path $Path -Filter *.sbc -Recurse | Where-Object { 
    $_.FullName -notmatch '\\(Prefabs|StorePrefabs)(\\|$)' 
}

$issuesFound = 0

function Get-TagValues($block, $tagName) {
    if ($block -match "\[$tagName\s*:\s*([^\]]+)\]") {
        $val = $matches[1].Trim()
        return ($val -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 }
    }
    return @()
}

foreach ($file in $files) {
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $lines = $content -split "`r?`n"

    # Line-by-line quick checks
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNum = $i + 1

        # Check 1: Zero-stripping in CustomCountersTargets
        if ($line -match '\[Custom(Sandbox)?CountersTargets:0\]' -or $line -match '\[Custom(Sandbox)?CountersTargets:.*,0(,|\])') {
            Write-Host "[ERROR] $($file.Name):$lineNum - Zero in CustomCountersTargets will be stripped by TagIntListCheck! Use -1 with Greater/LessOrEqual." -ForegroundColor Red
            $issuesFound++
        }

        # Check 2: WaypointNear / WaypointFar crash hazard
        if ($line -match '\[Type:Waypoint(Near|Far)\]') {
            Write-Host "[ERROR] $($file.Name):$lineNum - Type:WaypointNear/Far crashes trigger loops if CargoShipWaypoints is empty! Use TargetNear/Far instead." -ForegroundColor Red
            $issuesFound++
        }

        # Check 3: ChangeBlocksShareModeAll bug
        if ($line -match '\[ChangeBlocksShareModeAll:true\]') {
            Write-Host "[ERROR] $($file.Name):$lineNum - ChangeBlocksShareModeAll has an unhandled indexing bug in MES ActionSystem.cs!" -ForegroundColor Red
            $issuesFound++
        }

        # Check 4: CutVoxels on Spawn Conditions
        if ($line -match '\[CutVoxels:true\]') {
            Write-Host "[WARN] $($file.Name):$lineNum - [CutVoxels:true] does not exist on MES Spawn Conditions. Use [CutVoxelsAtAirtightCells:true] + [CutVoxelSize:double]." -ForegroundColor Yellow
            $issuesFound++
        }

        # Check 5: Tokens in [Actions:] profile names (statically resolved at load)
        if ($line -match '\[Actions:.*\{[a-zA-Z0-9_]+\}.*\]') {
            Write-Host "[ERROR] $($file.Name):$lineNum - Dynamic tokens inside [Actions:] profile names fail to load! Action profile names resolve statically at startup." -ForegroundColor Red
            $issuesFound++
        }
    }

    # Profile block checks (inside <Description>)
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '(?s)<Description>(.*?)</Description>')
    foreach ($dm in $descMatches) {
        $block = $dm.Groups[1].Value

        # Check 6: MES Event Action Master Gates & Lists
        if ($block -match '\[MES Event Action\]') {
            if ($block -match '\[Spawner:') {
                Write-Host "[ERROR] $($file.Name) - [Spawner:] tag does not work in MES Event Actions! Use [SpawnData:] instead." -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[Chat:') {
                Write-Host "[ERROR] $($file.Name) - [Chat:] tag does not work in MES Event Actions! Use [ChatData:] instead." -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\{Faction\}' -or $block -match '\{SpawnGroupName\}') {
                Write-Host "[ERROR] $($file.Name) - {Faction} and {SpawnGroupName} do not resolve in MES Events (npcData is null)!" -ForegroundColor Red
                $issuesFound++
            }

            # Master Gate: ChangeCounters
            if (($block -match '\[(Set|Increase|Decrease)Counters:' -or $block -match '\[(Set|Increase|Decrease)CountersAmount:') -and $block -notmatch '\[ChangeCounters:true\]') {
                Write-Host "[ERROR] $($file.Name) - Counter tags specified in [MES Event Action] without required [ChangeCounters:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }

            # Master Gate: ChangeBooleans
            if ($block -match '\[SetBooleans(True|False):' -and $block -notmatch '\[ChangeBooleans:true\]') {
                Write-Host "[ERROR] $($file.Name) - Boolean tags specified in [MES Event Action] without required [ChangeBooleans:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }

            # Master Gate: SpawnEncounter
            if (($block -match '\[Spawn(Data|Coords|FactionTags):') -and $block -notmatch '\[SpawnEncounter:true\]') {
                Write-Host "[ERROR] $($file.Name) - Spawner tags specified in [MES Event Action] without required [SpawnEncounter:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }

            # List Alignment Checks
            $setNames = Get-TagValues $block 'SetCounters'
            $setAmts = Get-TagValues $block 'SetCountersAmount'
            if ($setNames.Count -ne $setAmts.Count) {
                Write-Host "[ERROR] $($file.Name) - SetCounters count ($($setNames.Count)) does not match SetCountersAmount count ($($setAmts.Count))!" -ForegroundColor Red
                $issuesFound++
            }

            $incNames = Get-TagValues $block 'IncreaseCounters'
            $incAmts = Get-TagValues $block 'IncreaseCountersAmount'
            if ($incNames.Count -ne $incAmts.Count) {
                Write-Host "[ERROR] $($file.Name) - IncreaseCounters count ($($incNames.Count)) does not match IncreaseCountersAmount count ($($incAmts.Count))!" -ForegroundColor Red
                $issuesFound++
            }

            $decNames = Get-TagValues $block 'DecreaseCounters'
            $decAmts = Get-TagValues $block 'DecreaseCountersAmount'
            if ($decNames.Count -ne $decAmts.Count) {
                Write-Host "[ERROR] $($file.Name) - DecreaseCounters count ($($decNames.Count)) does not match DecreaseCountersAmount count ($($decAmts.Count))!" -ForegroundColor Red
                $issuesFound++
            }

            $spawnData = Get-TagValues $block 'SpawnData'
            $spawnCoords = Get-TagValues $block 'SpawnCoords'
            $spawnTags = Get-TagValues $block 'SpawnFactionTags'
            if ($spawnData.Count -gt 0) {
                if ($spawnData.Count -ne $spawnCoords.Count -or $spawnData.Count -ne $spawnTags.Count) {
                    Write-Host "[ERROR] $($file.Name) - SpawnEncounter list mismatch! SpawnData ($($spawnData.Count)), SpawnCoords ($($spawnCoords.Count)), SpawnFactionTags ($($spawnTags.Count)) must all be equal." -ForegroundColor Red
                    $issuesFound++
                }
            }
        }

        # Check 7: MES Event Condition Master Gates & Lists
        if ($block -match '\[MES Event Condition\]') {
            if ($block -match '\[CustomCounters:' -and $block -notmatch '\[CheckCustomCounters:true\]') {
                Write-Host "[ERROR] $($file.Name) - [CustomCounters:] specified in [MES Event Condition] without [CheckCustomCounters:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[TrueBooleans:' -and $block -notmatch '\[CheckTrueBooleans:true\]') {
                Write-Host "[ERROR] $($file.Name) - [TrueBooleans:] specified in [MES Event Condition] without [CheckTrueBooleans:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[FalseBooleans:' -and $block -notmatch '\[CheckFalseBooleans:true\]') {
                Write-Host "[ERROR] $($file.Name) - [FalseBooleans:] specified in [MES Event Condition] without [CheckFalseBooleans:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }

            # List Alignment: CustomCounters vs Targets
            $cNames = Get-TagValues $block 'CustomCounters'
            $cTargets = Get-TagValues $block 'CustomCountersTargets'
            if ($cNames.Count -ne $cTargets.Count) {
                Write-Host "[ERROR] $($file.Name) - CustomCounters count ($($cNames.Count)) does not match CustomCountersTargets count ($($cTargets.Count))!" -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 8: ActionExecution:Condition List Alignment (MES Events)
        if ($block -match '\[ActionExecution\s*:\s*Condition\]') {
            $condIds = Get-TagValues $block 'ConditionIds'
            $actIds = Get-TagValues $block 'ActionIds'
            if ($condIds.Count -ne $actIds.Count) {
                Write-Host "[ERROR] $($file.Name) - [ActionExecution:Condition] requires strictly equal ConditionIds ($($condIds.Count)) and ActionIds ($($actIds.Count)) counts!" -ForegroundColor Red
                $issuesFound++
            }
        }
    }
}

if ($issuesFound -eq 0) {
    Write-Host "MES Tag Audit Passed: No known tag hazards, master gate omissions, or list mismatches detected." -ForegroundColor Green
} else {
    Write-Host "MES Tag Audit Completed: $issuesFound issues/warnings flagged." -ForegroundColor Red
    exit 1
}
