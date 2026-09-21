<#
.SYNOPSIS
    Advanced semantic audit script for MES and RivalAI tags, master gates, and list alignments.
.DESCRIPTION
    Scans .sbc files for:
    1. Zero-stripping bugs across all affected tags (CustomCountersTargets, CustomSandboxCountersTargets, etc.).
    2. WaypointNear/WaypointFar trigger crash hazard.
    3. ChangeBlocksShareModeAll loop index bug.
    4. [CutVoxels:true] on Spawn Conditions (does not exist in MES).
    5. Missing activation flags ([UseTrigger:true], [UseSpawn:true], [UseChat:true], [UseEvent:true], [UseConditions:true]).
    6. Conflicting Autopilot flags (FlyLevelWithGravity + UseSurfaceHoverThrustMode).
    7. Boolean formatting errors (True, TRUE, 1 instead of true).
    8. RivalAI vs MES Event Action tag mismatches ([Spawner:] vs [SpawnData:], [Chat:] vs [ChatData:]).
    9. ContainerType master gates and list count mismatches in [MES Manipulation].
    10. ContainerType master gates and list count mismatches in [RivalAI Action].
    11. Missing boolean master gates and list count mismatches in [MES Event Action].
    12. Missing boolean master gates and list count mismatches in [MES Event Condition].
    13. Invalid token usage ({Faction} inside MES Events, tokens in [Actions:] profile names).
    14. Undefined or misspelled faction tags ([FactionOwner:], [FactionOverride:], [SpawnFactionTags:], [AllowedZoneFactions:], [RestrictedZoneFactions:]).
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

# Harvest declared factions from workspace Factions*.sbc files
$knownFactions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

# Primary known factions and reserved keywords (pass silently)
$primaryFactions = @(
    'SPRT', 'SPID',
    'Nobody', 'UseBaseGameFactionTags'
)
foreach ($pf in $primaryFactions) { [void]$knownFactions.Add($pf) }

# Obscure vanilla / economy / campaign factions (soft informational notice, does not fail audit)
$obscureVanillaFactions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$vanillaEconomyCampaign = @(
    'CIVL', 'TRAD', 'ROBO', 'FSD', 'STEJ', 'KRI', 'INDEP', 
    'SHIV', 'GTI', 'ROS', 'AMPH', 'BLDR', 'MINR', 'MILT', 'PIR8', 'RED', 'BLU'
)
foreach ($vf in $vanillaEconomyCampaign) { [void]$obscureVanillaFactions.Add($vf) }

$factionFiles = Get-ChildItem -Path $Path -Filter *Faction*.sbc -Recurse -ErrorAction SilentlyContinue
foreach ($ff in $factionFiles) {
    $fContent = [System.IO.File]::ReadAllText($ff.FullName)
    $tagMatches = [System.Text.RegularExpressions.Regex]::Matches($fContent, '<Tag>([^<]+)</Tag>')
    foreach ($tm in $tagMatches) {
        [void]$knownFactions.Add($tm.Groups[1].Value.Trim())
    }
    $attrMatches = [System.Text.RegularExpressions.Regex]::Matches($fContent, 'Tag="([^"]+)"')
    foreach ($am in $attrMatches) {
        [void]$knownFactions.Add($am.Groups[1].Value.Trim())
    }
}

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

    # Line-by-line checks
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNum = $i + 1

        # Check 1: Zero-stripping in all affected integer list tags
        if ($line -match '\[Custom(Sandbox)?CountersTargets:0\]' -or $line -match '\[Custom(Sandbox)?CountersTargets:.*,0(,|\])' -or
            $line -match '\[CustomZoneCounterValue:0\]' -or $line -match '\[CustomZoneCounterValue:.*,0(,|\])' -or
            $line -match '\[(Increase|Decrease)CountersAmount:0\]' -or $line -match '\[(Increase|Decrease)CountersAmount:.*,0(,|\])') {
            Write-Host "[ERROR] $($file.Name):$lineNum - Zero will be stripped by TagIntListCheck! Use -1 with Greater/LessOrEqual." -ForegroundColor Red
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

        # Check 6: Boolean formatting (case-sensitive check flagging True or TRUE)
        if ($line -cmatch '\[([a-zA-Z0-9_]+):(True|TRUE)\]') {
            $tName = $matches[1]
            Write-Host "[WARN] $($file.Name):$lineNum - Tag [$tName] specifies capitalized boolean '$($matches[2])'. Use lowercase 'true'." -ForegroundColor Yellow
            $issuesFound++
        }

        # Check 7: Debug tags in Action profiles (development diagnostic notice)
        if ($line -match '\[(DebugMessage|DebugChatMessage|DebugHudMessage):.*\]') {
            Write-Host "[WARN] $($file.Name):$lineNum - Debug tag [$($matches[1])] found. Ensure debug tags are removed before production release (do not use as substitute for NPC chat)." -ForegroundColor Yellow
        }

        # Check 14: Faction tag validation (detects typos that cause silent 0% spawn rate)
        if ($line -match '\[(FactionOwner|FactionOverride|CheckReputationAgainstOtherNPCFaction)\s*:\s*([^\]]+)\]') {
            $propName = $matches[1]
            $fTag = $matches[2].Trim()
            if ($fTag.Length -gt 0) {
                if ($fTag -match '^\{.*\}$') {
                    Write-Host "[ERROR] $($file.Name):$lineNum - Dynamic token '$fTag' in [${propName}:$fTag] cannot be resolved! Faction tags in spawn conditions/groups are evaluated pre-spawn before NpcData exists (IdsReplacer does not run here)." -ForegroundColor Red
                    $issuesFound++
                }
                elseif ($knownFactions.Contains($fTag)) {
                    # Known primary or declared faction - passes silently
                }
                elseif ($obscureVanillaFactions.Contains($fTag)) {
                    Write-Host "[INFO] $($file.Name):$lineNum - Faction tag '$fTag' in [${propName}:$fTag] is an obscure vanilla/economy faction. Verify this faction is active in world settings." -ForegroundColor Cyan
                }
                else {
                    Write-Host "[WARN] $($file.Name):$lineNum - Faction tag '$fTag' in [${propName}:$fTag] is not defined in any local Factions*.sbc or known factions! Spawning will silently fail ('Could Not Get Valid NPC Faction')." -ForegroundColor Yellow
                    $issuesFound++
                }
            }
        }
        if ($line -match '\[(AllowedZoneFactions|RestrictedZoneFactions|SpawnFactionTags)\s*:\s*([^\]]+)\]') {
            $propName = $matches[1]
            $rawList = $matches[2].Trim()
            foreach ($item in ($rawList -split ',')) {
                $fTag = $item.Trim()
                if ($fTag.Length -gt 0) {
                    if ($fTag -match '^\{.*\}$') {
                        Write-Host "[ERROR] $($file.Name):$lineNum - Dynamic token '$fTag' in [${propName}:$rawList] cannot be resolved! Faction tags in spawn conditions/groups are evaluated pre-spawn before NpcData exists (IdsReplacer does not run here)." -ForegroundColor Red
                        $issuesFound++
                    }
                    elseif ($knownFactions.Contains($fTag)) {
                        # Known primary or declared faction - passes silently
                    }
                    elseif ($obscureVanillaFactions.Contains($fTag)) {
                        Write-Host "[INFO] $($file.Name):$lineNum - Faction tag '$fTag' in [${propName}:$rawList] is an obscure vanilla/economy faction. Verify this faction is active in world settings." -ForegroundColor Cyan
                    }
                    else {
                        Write-Host "[WARN] $($file.Name):$lineNum - Faction tag '$fTag' in [${propName}:$rawList] is not defined in any local Factions*.sbc or known factions! Spawning will silently fail ('Could Not Get Valid NPC Faction')." -ForegroundColor Yellow
                        $issuesFound++
                    }
                }
            }
        }
    }

    # Profile block checks (inside <Description>)
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '(?s)<Description>(.*?)</Description>')
    foreach ($dm in $descMatches) {
        $block = $dm.Groups[1].Value

        # Check 7: Missing Activation Gates
        if (($block -match '\[(RivalAI|MES AI) Trigger\]') -and ($block -notmatch '\[UseTrigger:true\]' -and $block -notmatch '\[UseTrigger:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Trigger] is missing required [UseTrigger:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[(RivalAI|MES AI) Spawn\]') -and ($block -notmatch '\[UseSpawn:true\]' -and $block -notmatch '\[UseSpawn:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Spawn] is missing required [UseSpawn:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[(RivalAI|MES AI) Chat\]') -and ($block -notmatch '\[UseChat:true\]' -and $block -notmatch '\[UseChat:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Chat] is missing required [UseChat:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[MES Event\]') -and ($block -notmatch '\[UseEvent:true\]' -and $block -notmatch '\[UseEvent:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [MES Event] is missing required [UseEvent:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }
        if (($block -match '\[(RivalAI|MES AI) Condition\]') -and ($block -notmatch '\[UseConditions:true\]' -and $block -notmatch '\[UseConditions:false\]')) {
            Write-Host "[ERROR] $($file.Name) - [RivalAI Condition] is missing required [UseConditions:true] activation tag!" -ForegroundColor Red
            $issuesFound++
        }

        # Check 8: Autopilot Conflicts
        if ($block -match '\[(RivalAI|MES AI) Autopilot\]') {
            if ($block -match '\[FlyLevelWithGravity:true\]' -and $block -match '\[UseSurfaceHoverThrustMode:true\]') {
                Write-Host "[ERROR] $($file.Name) - Autopilot declares both [FlyLevelWithGravity:true] and [UseSurfaceHoverThrustMode:true]! This causes severe physics oscillation." -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 9: MES Manipulation ContainerType Master Gates & Lists
        if ($block -match '\[MES Manipulation\]') {
            if (($block -match '\[ContainerTypeAssignBlockName:' -or $block -match '\[ContainerTypeAssignSubtypeId:') -and $block -notmatch '\[UseContainerTypeAssignment:true\]') {
                Write-Host "[ERROR] $($file.Name) - ContainerType assignment tags specified in [MES Manipulation] without required [UseContainerTypeAssignment:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            $ctBlockNames = Get-TagValues $block 'ContainerTypeAssignBlockName'
            $ctSubtypeIds = Get-TagValues $block 'ContainerTypeAssignSubtypeId'
            if ($ctBlockNames.Count -ne $ctSubtypeIds.Count) {
                Write-Host "[ERROR] $($file.Name) - ContainerTypeAssignBlockName count ($($ctBlockNames.Count)) does not match ContainerTypeAssignSubtypeId count ($($ctSubtypeIds.Count))! MES will silently drop all assignments." -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 10: RivalAI Action ContainerType Master Gates & Lists
        if ($block -match '\[(RivalAI|MES AI) Action\]') {
            if (($block -match '\[ContainerTypeBlockNames:' -or $block -match '\[ContainerTypeSubtypeIds:') -and $block -notmatch '\[ApplyContainerTypeToInventoryBlock:true\]') {
                Write-Host "[ERROR] $($file.Name) - ContainerType tags specified in [RivalAI Action] without required [ApplyContainerTypeToInventoryBlock:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            $actCtBlocks = Get-TagValues $block 'ContainerTypeBlockNames'
            $actCtSubtypes = Get-TagValues $block 'ContainerTypeSubtypeIds'
            if ($actCtBlocks.Count -ne $actCtSubtypes.Count) {
                Write-Host "[ERROR] $($file.Name) - ContainerTypeBlockNames count ($($actCtBlocks.Count)) does not match ContainerTypeSubtypeIds count ($($actCtSubtypes.Count))!" -ForegroundColor Red
                $issuesFound++
            }
        }

        # Check 11: MES Event Action Master Gates & Lists
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

            # Master Gates
            if (($block -match '\[(Set|Increase|Decrease)Counters:' -or $block -match '\[(Set|Increase|Decrease)CountersAmount:') -and $block -notmatch '\[ChangeCounters:true\]') {
                Write-Host "[ERROR] $($file.Name) - Counter tags specified in [MES Event Action] without required [ChangeCounters:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[SetBooleans(True|False):' -and $block -notmatch '\[ChangeBooleans:true\]') {
                Write-Host "[ERROR] $($file.Name) - Boolean tags specified in [MES Event Action] without required [ChangeBooleans:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if (($block -match '\[Spawn(Data|Coords|FactionTags):') -and $block -notmatch '\[SpawnEncounter:true\]') {
                Write-Host "[ERROR] $($file.Name) - Spawner tags specified in [MES Event Action] without required [SpawnEncounter:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[Zone(Names|RadiusChangeTypes|RadiusChangeAmounts):' -and $block -notmatch '\[ChangeZoneByName:true\]') {
                Write-Host "[ERROR] $($file.Name) - Zone modification tags specified in [MES Event Action] without required [ChangeZoneByName:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }
            if ($block -match '\[ToggleEvent(Ids|IdModes|Tags|TagModes):' -and $block -notmatch '\[ToggleEvents:true\]') {
                Write-Host "[ERROR] $($file.Name) - ToggleEvent tags specified in [MES Event Action] without required [ToggleEvents:true] master gate!" -ForegroundColor Red
                $issuesFound++
            }

            # List Alignments
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

        # Check 12: MES Event Condition Master Gates & Lists
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

            $cNames = Get-TagValues $block 'CustomCounters'
            $cTargets = Get-TagValues $block 'CustomCountersTargets'
            if ($cNames.Count -ne $cTargets.Count) {
                Write-Host "[ERROR] $($file.Name) - CustomCounters count ($($cNames.Count)) does not match CustomCountersTargets count ($($cTargets.Count))!" -ForegroundColor Red
                $issuesFound++
            }
        }
    }
}

Write-Host ""
if ($issuesFound -eq 0) {
    Write-Host "MES Tag Audit Passed: No tag hazards, master gate omissions, or list mismatches detected." -ForegroundColor Green
    exit 0
} else {
    Write-Host "MES Tag Audit Completed: $issuesFound issue(s)/warning(s) flagged." -ForegroundColor Red
    exit 1
}
