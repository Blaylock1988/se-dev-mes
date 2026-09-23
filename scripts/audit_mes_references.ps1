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
       - Loot/Manipulation profiles: [ContainerTypes], [ContainerTypeAssignSubtypeId],
         [AssignContainerTypesToAllCargo]
    3. Collect and cross-reference the separate string-Tag broadcast system, distinct from
       SubtypeId lookups: [Tags:] declared on [RivalAI Trigger]/[MES AI Trigger] profiles
       and on [MES Event] profiles (two independent, non-unique, many-to-many pools - by
       design many profiles legitimately share one tag so a single broadcast can act on all
       of them at once, so - unlike SubtypeIds - Tags are never flagged as "duplicate
       definitions"). Consumers: [ManuallyActivatedTriggerTags:], [EnableTriggerTags:],
       [DisableTriggerTags:], [ResetTriggerCooldownTags:] (match the Trigger-tag pool) and
       [ActivateEventTags:], [ToggleEventTags:], [ResetEventCooldownTags:],
       [IncreaseRunCountEventTags:] (match the Event-tag pool). A tag referenced that no
       profile anywhere declares is flagged - the broadcast would silently do nothing.
    4. Cross-reference definitions and references to flag:
       - Missing / Dangling references (referenced but never defined)
       - Case mismatches (e.g. 'GVK-Action-Foo' vs 'GVK-Action-foo')
       - Orphaned definitions (defined but never referenced anywhere)

    Known false-positive sources this script deliberately suppresses, and how:
    - References to profiles shipped inside MES's own Data folder (e.g.
      MES-Manipulation-RivalAi) are resolved against scripts/mes_core_definitions.json
      instead of being flagged as missing.
    - References containing a runtime token (e.g. '{Faction}-Convoy') are only treated as
      possibly-resolvable for the small set of reference types confirmed (against the MES
      C# source) to have ANY substitution mechanism at all: SpawnGroup, Store, ToggleEvent,
      ResetEvent. For those, the token is turned into a wildcard and checked against every
      known definition: at least one match -> [INFO] Dynamic Token Reference (real, just
      not statically pinpointable); zero matches -> [ERROR] Dead Token Pattern (dead
      regardless of substitution - a real bug). For every OTHER reference type (Action,
      Trigger, Condition, TriggerGroup, ManipulationProfiles, LootProfiles, ContainerType,
      etc.) a token is flagged immediately as [ERROR] Token in Static Reference, because
      MES has no substitution mechanism for those tags at all - a token there is always
      dead on arrival, not a false positive. See the Pass 2 comment block for full
      source-verified evidence per reference type.
    - Files matching '*ContainerTypes*.sbc' are parsed with a dedicated block-aware rule:
      only the <ContainerType>'s own <Id><TypeId>ContainerTypeDefinition</TypeId>
      <SubtypeId> is registered as a definition. The <Items><Item><Id><SubtypeId> entries
      nested inside are commodity items (ore/ingot/component ids like Uranium), not MES
      profile definitions, and legitimately repeat across dozens of container types - so
      they are not registered and do not trigger duplicate-definition noise. Loot
      references ([ContainerTypes:], [ContainerTypeAssignSubtypeId:],
      [AssignContainerTypesToAllCargo:]) ARE still validated against real container-type
      definitions, MES's own shipped container types, and vanilla SE's stock container
      types (scripts/vanilla_container_types.json) - so a typo'd or non-existent loot
      table is still caught.
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
    [switch]$SkipPrefabs = $false,
    [switch]$WarnOrphans = $false
)

Write-Host "Scanning SBC files in: $Path" -ForegroundColor Cyan

# 1. Collect all .sbc files
$sbcFiles = Get-ChildItem -Path $Path -Filter *.sbc -Recurse
if ($sbcFiles.Count -eq 0) {
    Write-Host "No .sbc files found in $Path" -ForegroundColor Red
    exit 1
}

# SubtypeIds shipped natively by MES itself (RivalAI/manipulation/loot/spawn-condition
# profiles that live inside MES's own Data folder, not in the mod being audited).
# Referencing one of these is not a missing reference. Regenerate this list when MES
# updates — see scripts/mes_core_definitions.json for the extraction command.
$mesCoreDefinitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$mesCoreDefPath = Join-Path $PSScriptRoot "mes_core_definitions.json"
if (Test-Path $mesCoreDefPath) {
    try {
        $mesCoreData = Get-Content -Raw $mesCoreDefPath | ConvertFrom-Json
        foreach ($d in $mesCoreData.definitions) { [void]$mesCoreDefinitions.Add($d) }
    } catch {
        Write-Host "[WARN] Could not parse mes_core_definitions.json - MES core profiles will not be recognized: $_" -ForegroundColor Yellow
    }
}

# ContainerTypeDefinition SubtypeIds shipped by vanilla Space Engineers itself (e.g.
# PersonalContainerSmall). A [ContainerTypes:]/[ContainerTypeAssignSubtypeId:] reference
# to one of these is valid even though it's never defined in this mod or in MES.
$vanillaContainerTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$vanillaContainerTypesPath = Join-Path $PSScriptRoot "vanilla_container_types.json"
if (Test-Path $vanillaContainerTypesPath) {
    try {
        $vanillaCtData = Get-Content -Raw $vanillaContainerTypesPath | ConvertFrom-Json
        foreach ($d in $vanillaCtData.definitions) { [void]$vanillaContainerTypes.Add($d) }
    } catch {
        Write-Host "[WARN] Could not parse vanilla_container_types.json - vanilla container types will not be recognized: $_" -ForegroundColor Yellow
    }
}

# ContainerTypes.sbc files use vanilla SE's loot-table schema: a <ContainerType> block's
# own <Id><TypeId>ContainerTypeDefinition</TypeId><SubtypeId> is the real, referenceable
# definition; everything inside its nested <Items><Item><Id><SubtypeId> is a commodity
# item (ore/ingot/component id) that legitimately repeats across many container types and
# is never referenced by MES tags. These files get dedicated block-level parsing instead
# of the generic per-line SubtypeId scan below.
function Test-IsContainerTypesFile($file) {
    return $file.Name -match 'ContainerTypes'
}

function Get-LineNumberAtIndex($content, $index) {
    return ($content.Substring(0, $index) -split "`n").Count
}

# Turns a reference name containing runtime tokens (e.g. 'Foo-{Faction}-Bar') into a
# regex that treats each token as a wildcard, so it can be checked against every known
# definition to see whether ANY substitution could ever resolve it.
function Convert-TokenRefToPattern([string]$name) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('^')
    $pos = 0
    foreach ($tm in [regex]::Matches($name, '\{[^}]+\}')) {
        if ($tm.Index -gt $pos) {
            [void]$sb.Append([regex]::Escape($name.Substring($pos, $tm.Index - $pos)))
        }
        [void]$sb.Append('.+')
        $pos = $tm.Index + $tm.Length
    }
    if ($pos -lt $name.Length) {
        [void]$sb.Append([regex]::Escape($name.Substring($pos)))
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

# Dictionaries to track definitions: Name -> @{ File = $file; Line = $line; ExactName = $name; Type = $type }
$definitions = @{}
$definitionsLower = @{}

# List of references: @{ Name = $name; File = $file; Line = $line; RefType = $refType }
$references = [System.Collections.Generic.List[PSObject]]::new()

# --- String-Tag broadcast system (separate from SubtypeId lookups; see MES source:
# TriggerProfile.Tags / EventProfile.Tags, TagParse.TagStringListCheck, and the
# ToggleTagTriggers/ManuallyActivateTrigger/ActivateEvent/ToggleEvents match loops in
# ActionSystem.cs / TriggerSystem.cs / EventActionExecution.cs). Two independent pools:
# a Trigger-tag string only ever matches other Trigger-declared tags, and an Event-tag
# string only ever matches other Event-declared tags. Matching is ordinal (case-sensitive)
# List<string>.Contains() everywhere - never fuzzy - and many profiles legitimately share
# one tag on purpose (a broadcast is meant to hit all of them), so these pools are NOT
# unique-key definitions and must never get a "duplicate definition" warning.
$triggerTagDefinitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$eventTagDefinitions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$tagReferences = [System.Collections.Generic.List[PSObject]]::new()

function Register-TagReference($names, $file, $refType, $pool, $tokenResolves) {
    if ($null -eq $names) { return }
    foreach ($n in $names) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $tagReferences.Add([PSCustomObject]@{
            Name = $n.Trim()
            File = $file
            RefType = $refType
            Pool = $pool
            TokenResolves = $tokenResolves
        })
    }
}

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
    # MES allows some tags to either take a comma list on one line, OR be repeated on
    # separate lines within the same profile (e.g. GVK's [MES Loot] profiles list one
    # [ContainerTypes:X] per line rather than a single comma-separated tag). A single
    # -match only captures the first occurrence, so every occurrence must be collected.
    $results = [System.Collections.Generic.List[string]]::new()
    $tagMatches = [regex]::Matches($block, "\[$tagName\s*:\s*([^\]]+)\]")
    foreach ($tm in $tagMatches) {
        $val = $tm.Groups[1].Value.Trim()
        foreach ($v in ($val -split ',')) {
            $vTrim = $v.Trim()
            if ($vTrim.Length -gt 0) { $results.Add($vTrim) }
        }
    }
    return $results
}

# Scan pass 1: Collect definitions and references
foreach ($file in $sbcFiles) {
    $isPrefab = $file.FullName -match '\\(Prefabs|StorePrefabs)(\\|$)'
    if ($isPrefab -and -not $IncludePrefabs) { continue }

    $content = [System.IO.File]::ReadAllText($file.FullName)
    $lines = $content -split "`r?`n"
    $isContainerTypesFile = Test-IsContainerTypesFile $file

    if ($isContainerTypesFile) {
        # Only the ContainerType's own Id (TypeId=ContainerTypeDefinition) is a
        # definition - nested <Items><Item> commodity SubtypeIds are deliberately not
        # registered at all (see header comment).
        $ctMatches = [regex]::Matches($content, '(?s)<Id>\s*<TypeId>ContainerTypeDefinition</TypeId>\s*<SubtypeId>([^<]+)</SubtypeId>\s*</Id>')
        foreach ($cm in $ctMatches) {
            $subId = $cm.Groups[1].Value.Trim()
            $lineNum = Get-LineNumberAtIndex $content $cm.Index
            Register-Definition $subId $file $lineNum "ContainerTypeDefinition"
        }
    } else {
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
    }

    # Description profile block references
    $descMatches = [System.Text.RegularExpressions.Regex]::Matches($content, '(?s)<Description>(.*?)</Description>')
    foreach ($dm in $descMatches) {
        $block = $dm.Groups[1].Value

        # --- String-Tag pool membership: which pool a [Tags:] declaration in THIS block
        # belongs to depends on the profile type marker present in the block (TriggerProfile
        # vs EventProfile are separate C# classes with separate Tags fields/pools).
        $isTriggerProfile = $block -match '\[(RivalAI|MES AI) Trigger\]'
        $isEventProfile = $block -match '\[MES Event\]'
        # ActionReferenceProfile.cs (RivalAI/MES AI Action, live NpcData via ActionSystem.cs)
        # and EventActionReference.cs (MES Event Action, npcData=null) are SEPARATE C# classes
        # that happen to both declare ToggleEvent*/ResetEventCooldown* fields - confirmed by
        # reading both files directly. Same tag name, different token behavior depending on
        # which block it's declared in.
        $isRivalAIAction = $block -match '\[(RivalAI|MES AI) Action\]'
        if ($isTriggerProfile) {
            foreach ($t in (Parse-CsvTags $block 'Tags')) { [void]$triggerTagDefinitions.Add($t) }
        }
        if ($isEventProfile) {
            foreach ($t in (Parse-CsvTags $block 'Tags')) { [void]$eventTagDefinitions.Add($t) }
        }

        # Trigger-tag pool consumers - all confirmed to run through IdsReplacer with live
        # NpcData (RivalAI Behavior/Trigger Action context: ActionSystem.cs/TriggerSystem.cs).
        # These fields exist ONLY on ActionReferenceProfile.cs (confirmed no MES-Events
        # equivalent), so unlike Toggle/ResetEventCooldown below they don't need block-type
        # gating - they always token-resolve.
        Register-TagReference (Parse-CsvTags $block 'ManuallyActivatedTriggerTags') $file "ManuallyActivatedTriggerTags" "Trigger" $true
        Register-TagReference (Parse-CsvTags $block 'EnableTriggerTags') $file "EnableTriggerTags" "Trigger" $true
        Register-TagReference (Parse-CsvTags $block 'DisableTriggerTags') $file "DisableTriggerTags" "Trigger" $true
        Register-TagReference (Parse-CsvTags $block 'ResetTriggerCooldownTags') $file "ResetTriggerCooldownTags" "Trigger" $true

        # Event-tag pool consumers. [ActivateEventTags:] exists ONLY on the RivalAI side
        # (live NpcData, always token-resolves) - a cross-system bridge into MES Events.
        # [ToggleEventTags:]/[ResetEventCooldownTags:] are declared on BOTH
        # ActionReferenceProfile.cs (RivalAI/MES AI Action - wrapped in IdsReplacer at
        # ActionSystem.cs, token-resolves) AND EventActionReference.cs (MES Event Action -
        # npcData=null, NOT wrapped in IdsReplacer at EventActionExecution.cs, tokens dead) -
        # so which one applies depends on the block's own profile-type marker.
        # [IncreaseRunCountEventTags:] exists ONLY on the MES-Events side - always dead.
        Register-TagReference (Parse-CsvTags $block 'ActivateEventTags') $file "ActivateEventTags" "Event" $true
        Register-TagReference (Parse-CsvTags $block 'ToggleEventTags') $file "ToggleEventTags" "Event" $isRivalAIAction
        Register-TagReference (Parse-CsvTags $block 'ResetEventCooldownTags') $file "ResetEventCooldownTags" "Event" $isRivalAIAction
        Register-TagReference (Parse-CsvTags $block 'IncreaseRunCountEventTags') $file "IncreaseRunCountEventTags" "Event" $false

        # Name-based siblings of the tag broadcasts above - these ARE plain SubtypeId
        # lookups (not the Tag pool), so they reuse the existing SubtypeId reference system.
        # Both are confirmed to token-resolve via IdsReplacer (live NpcData, same call sites
        # as their *Tags siblings above) - given their own RefType rather than reusing
        # "Trigger"/generic, since a plain [Triggers:] reference does NOT token-resolve and
        # must not be silently exempted by sharing a token-aware RefType.
        Register-Reference (Parse-CsvTags $block 'ManuallyActivatedTriggerNames') $file 0 "ManuallyActivatedTriggerNames"
        Register-Reference (Parse-CsvTags $block 'ActivateEventIds') $file 0 "Event"

        # Remote Control / Behavior references
        Register-Reference (Parse-CsvTags $block 'Triggers') $file 0 "Trigger"
        Register-Reference (Parse-CsvTags $block 'TriggerGroups') $file 0 "TriggerGroup"
        Register-Reference (Parse-CsvTags $block 'AutopilotData') $file 0 "Autopilot"
        Register-Reference (Parse-CsvTags $block 'SecondaryAutopilotData') $file 0 "Autopilot"
        Register-Reference (Parse-CsvTags $block 'TargetData') $file 0 "Target"
        Register-Reference (Parse-CsvTags $block 'WeaponProfiles') $file 0 "WeaponSystem"

        # Trigger references
        Register-Reference (Parse-CsvTags $block 'Conditions') $file 0 "Condition"
        Register-Reference (Parse-CsvTags $block 'Actions') $file 0 "Action"
        Register-Reference (Parse-CsvTags $block 'ToggleWithTriggerProfile') $file 0 "Trigger"

        # Action references
        Register-Reference (Parse-CsvTags $block 'Spawner') $file 0 "Spawner"
        Register-Reference (Parse-CsvTags $block 'SpawnData') $file 0 "SpawnData"
        Register-Reference (Parse-CsvTags $block 'Chat') $file 0 "Chat"
        Register-Reference (Parse-CsvTags $block 'ChatData') $file 0 "ChatData"
        Register-Reference (Parse-CsvTags $block 'CommandProfileIds') $file 0 "CommandProfile"
        # Same dual-context split as ToggleEventTags/ResetEventCooldownTags above:
        # token-resolves only when declared inside a [RivalAI Action]/[MES AI Action] block.
        Register-Reference (Parse-CsvTags $block 'ToggleEventIds') $file 0 $(if ($isRivalAIAction) { "ToggleEvent" } else { "ToggleEventStatic" })
        Register-Reference (Parse-CsvTags $block 'ResetEventCooldownIds') $file 0 $(if ($isRivalAIAction) { "ResetEvent" } else { "ResetEventStatic" })
        Register-Reference (Parse-CsvTags $block 'SafeZoneProfile') $file 0 "SafeZone"
        Register-Reference (Parse-CsvTags $block 'StoreProfiles') $file 0 "Store"

        # Spawner references
        Register-Reference (Parse-CsvTags $block 'SpawnGroups') $file 0 "SpawnGroup"

        # SpawnGroup & Manipulation references
        Register-Reference (Parse-CsvTags $block 'SpawnConditionsProfiles') $file 0 "SpawnCondition"
        Register-Reference (Parse-CsvTags $block 'DerelictionProfiles') $file 0 "Dereliction"
        Register-Reference (Parse-CsvTags $block 'ManipulationProfiles') $file 0 "Manipulation"
        Register-Reference (Parse-CsvTags $block 'BlockReplacementProfiles') $file 0 "BlockReplacement"
        Register-Reference (Parse-CsvTags $block 'LootProfiles') $file 0 "Loot"
        Register-Reference (Parse-CsvTags $block 'LootGroups') $file 0 "LootGroup"
        Register-Reference (Parse-CsvTags $block 'ReplenishProfiles') $file 0 "Replenishment"

        # Store references
        Register-Reference (Parse-CsvTags $block 'StoreItems') $file 0 "StoreItem"

        # Container-type / loot-table references (validated against local
        # ContainerType definitions, MES's shipped types, and vanilla SE's stock types)
        Register-Reference (Parse-CsvTags $block 'ContainerTypes') $file 0 "ContainerType"
        Register-Reference (Parse-CsvTags $block 'ContainerTypeAssignSubtypeId') $file 0 "ContainerType"
        Register-Reference (Parse-CsvTags $block 'AssignContainerTypesToAllCargo') $file 0 "ContainerType"

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
    if ($refName -in @("true", "false", "None", "Default", "Primary", "Secondary")) { continue }
    if ($ref.RefType -eq "SpawnGroupPrefab" -and $SkipPrefabs) { continue }

    # Runtime tokens (e.g. {Faction}, {SpawnGroupName}) are substituted by IdsReplacer.cs -
    # or, for [SpawnGroups:] specifically inside MES Events, by a separate bespoke
    # {Faction}-only replace fed from [SpawnFactionTags:] - but ONLY for a small, fixed set
    # of reference types. Verified end-to-end against the MES C# source
    # (ActionSystem.cs, EventActionExecution.cs, SpawnGroupManager.cs): every substitution
    # path is a plain literal string.Replace(), and every downstream lookup is an ordinary
    # exact-match List.Contains()/dictionary lookup - there is no wildcard or pooled-name
    # matching anywhere in MES itself. A profile-name reference like [Actions:], [Triggers:],
    # [Conditions:], [TriggerGroups:], [ManipulationProfiles:], [LootProfiles:], or
    # [ContainerTypes:] has NO substitution mechanism at all - a token there is dead on
    # arrival, not a false positive, so it's flagged immediately regardless of whether some
    # unrelated definition happens to match the pattern.
    #
    # For the confirmed token-aware types below, the token is turned into a wildcard and
    # checked against every known definition: at least one match means the pattern is live
    # for some substitution (a real reference, not statically pinpointable further); zero
    # matches means the reference is dead no matter what gets substituted in - a genuine,
    # catchable typo/misconfiguration.
    #   - SpawnGroup   -> IdsReplacer (RivalAI Behavior Trigger Action, live NpcData)
    #                      AND a separate hardcoded {Faction}-only replace fed from
    #                      [SpawnFactionTags:] (MES Event SpawnEncounter action)
    #   - Store        -> IdsReplacer (RivalAI Behavior Trigger Action, live NpcData only -
    #                      NOT confirmed to resolve if this profile is instead invoked via
    #                      an MES Event's [ActionIds:] chain)
    #   - ToggleEvent, ResetEvent -> IdsReplacer (RivalAI Behavior Trigger Action, live
    #                      NpcData only - same RivalAI-only caveat as Store)
    #   - ManuallyActivatedTriggerNames, Event (from [ActivateEventIds:]) -> IdsReplacer,
    #                      same RivalAI Behavior/live-NpcData call sites as their *Tags
    #                      siblings in the string-Tag system below
    $tokenAwareRefTypes = @("SpawnGroup", "Store", "ToggleEvent", "ResetEvent", "ManuallyActivatedTriggerNames", "Event")
    if ($refName -match '\{[^}]+\}') {
        if ($tokenAwareRefTypes -notcontains $ref.RefType) {
            Write-Host "[ERROR] Token in Static Reference ($($ref.RefType)): '$refName' in $($ref.File.Name) contains a runtime token, but MES has no substitution mechanism for $($ref.RefType) references (confirmed against source - always a literal SubtypeId lookup). This will always fail to find the profile, regardless of context." -ForegroundColor Red
            $errors++
            continue
        }

        $tokenPattern = Convert-TokenRefToPattern $refName
        $wildcardMatch =
            ($definitions.Keys | Where-Object { $_ -match $tokenPattern } | Select-Object -First 1) -or
            ($mesCoreDefinitions | Where-Object { $_ -match $tokenPattern } | Select-Object -First 1) -or
            ($vanillaContainerTypes | Where-Object { $_ -match $tokenPattern } | Select-Object -First 1)
        if ($wildcardMatch) {
            Write-Host "[INFO] Dynamic Token Reference ($($ref.RefType)): '$refName' in $($ref.File.Name) contains a runtime token that MES CAN substitute for this reference type; matches at least one real definition as a wildcard, so the pattern is live - not further verifiable statically, skipped." -ForegroundColor DarkCyan
        } else {
            Write-Host "[ERROR] Dead Token Pattern ($($ref.RefType)): '$refName' in $($ref.File.Name) does not match ANY defined profile even with its token(s) treated as a wildcard - this reference can never resolve to anything, no matter what gets substituted in!" -ForegroundColor Red
            $errors++
        }
        continue
    }

    # Built-in MES core profile (ships inside the MES mod itself, not this mod).
    if ($mesCoreDefinitions.Contains($refName)) { continue }

    # Stock vanilla SE container type (ContainerType references only).
    if ($ref.RefType -eq "ContainerType" -and $vanillaContainerTypes.Contains($refName)) { continue }

    if (-not $definitionsLower.ContainsKey($refLower)) {
        Write-Host "[ERROR] Missing Reference ($($ref.RefType)): '$refName' referenced in $($ref.File.Name) is not defined anywhere!" -ForegroundColor Red
        $errors++
    } elseif (-not $definitions.ContainsKey($refName)) {
        $actual = $definitionsLower[$refLower].ExactName
        Write-Host "[WARN] Case Mismatch ($($ref.RefType)): '$refName' in $($ref.File.Name) does not match definition '$actual' in $($definitionsLower[$refLower].File.Name)" -ForegroundColor Yellow
        $warnings++
    }
}

# Pass 2b: Validate string-Tag broadcast references (Trigger-tag and Event-tag pools are
# separate namespaces - see the Register-TagReference block above for why). Matching is
# ordinal/case-sensitive to mirror MES's own List<string>.Contains() semantics exactly.
Write-Host "Trigger Tags Declared: $($triggerTagDefinitions.Count) | Event Tags Declared: $($eventTagDefinitions.Count) | Tag References Checked: $($tagReferences.Count)" -ForegroundColor Gray
foreach ($tref in $tagReferences) {
    $tagName = $tref.Name
    $pool = if ($tref.Pool -eq "Trigger") { $triggerTagDefinitions } else { $eventTagDefinitions }
    $poolLabel = if ($tref.Pool -eq "Trigger") { "Trigger-tag" } else { "Event-tag" }

    if ($tagName -match '\{[^}]+\}') {
        if (-not $tref.TokenResolves) {
            Write-Host "[ERROR] Token in Non-Resolving Tag ($($tref.RefType)): '$tagName' in $($tref.File.Name) contains a runtime token, but this tag field runs inside MES Events (npcData is null) with no IdsReplacer wrapping - confirmed against source (EventActionExecution.cs). The token never resolves, so this broadcast will always target a literal string containing '{...}' that no [Tags:] declaration can ever match." -ForegroundColor Red
            $errors++
            continue
        }
        $tokenPattern = Convert-TokenRefToPattern $tagName
        $wildcardMatch = $pool | Where-Object { $_ -match $tokenPattern } | Select-Object -First 1
        if ($wildcardMatch) {
            Write-Host "[INFO] Dynamic Token Tag Reference ($($tref.RefType)): '$tagName' in $($tref.File.Name) contains a runtime token resolved by IdsReplacer before matching; matches at least one declared $poolLabel as a wildcard, so the pattern is live - not further verifiable statically, skipped." -ForegroundColor DarkCyan
        } else {
            Write-Host "[ERROR] Dead Token Tag Pattern ($($tref.RefType)): '$tagName' in $($tref.File.Name) does not match ANY declared $poolLabel even with its token(s) treated as a wildcard - this broadcast can never hit anything, no matter what gets substituted in!" -ForegroundColor Red
            $errors++
        }
        continue
    }

    if (-not $pool.Contains($tagName)) {
        Write-Host "[ERROR] Undeclared Tag ($($tref.RefType)): '$tagName' in $($tref.File.Name) does not match any declared $poolLabel ([Tags:] on a matching profile) - this broadcast silently does nothing (MES's tag match is an exact List.Contains(), no error is logged)." -ForegroundColor Red
        $errors++
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

