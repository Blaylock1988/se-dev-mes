---
name: se-dev-mes
description: "Modular Encounters Systems (MES) and RivalAI modding guide for Space Engineers version 1. Covers MES Events vs RivalAI Grid Triggers, tag dictionaries, boolean master gates, XML deserialization quirks, zero-stripping bugs, spawner setups, sandbox variable persistence, economy store grid sales, and verified engine workarounds."
license: MIT
allowed-tools: Read, run_command
---

# SE Dev MES & RivalAI Modding Guide

**Applies to Space Engineers version 1 with Modular Encounters Systems (MES) and RivalAI.**

MES/RivalAI quirks, SBC pitfalls, and engineering standards for NPC-heavy (especially planet-rover and encounter) servers.

**Reading Guide - Claim Classification**:
- **[HARD]** = Enforced by the installed MES build or the SE engine itself. Violations cause deterministic failure (crash, silent no-op, profile load failure). Verified against the local MES source code.
- **[SOFT]** = Field-tested heuristic from live-server operation, not pinned to a specific code path. An MES or SE update can invalidate it; treat as a starting point and re-validate if behavior changes.

---

## 1. Modular Encounters Systems (MES) Source of Truth

- **Framework Overview**: Workshop ID `1521905890` (Author: Meridius_IX / Lucas). MES acts as a spawning and AI routing shell for custom NPC ships, drones, stations, and encounters.
- **Vanilla Spawning Suppression**: On session load, MES automatically disables vanilla cargo ships, random encounters, and planetary creatures (wolves/spiders) — replacing them with its own systems.
- **Integration APIs & Hooks**: MES exposes event hooks and callbacks for major third-party frameworks:
  - **CoreSystems (WeaponCore / WC)**: Weapon targeting, range overrides, and custom weapon replacement.
  - **Defense Shields**: Shield modulation and damage filtering.
  - **AiEnabled**: Crew bot and combat bot spawning on NPC grids.
  - **Water Mod** & **Nebula Mod**: Hydrodynamic and atmospheric environment checks.
- **WebWiki Is Outdated**: Online wikis and guides lack the newest features, contain human errors, or describe obsolete workarounds.
- **Physical Codebase Reference**: Always verify tag names, casing, and logic against the local MES source code (typically `%AppData%\SpaceEngineers\Mods\Modular-Encounters-Systems\Data\Scripts\ModularEncountersSystems` on Windows dev installs).
- **Key Inspection Targets**:
  - `Spawning/Profiles/ImprovedSpawnGroup.cs` & `SpawnConditionsProfile.cs` (Spawning & conditions)
  - `Spawning/Manipulation/` (WeaponRandomizer, BlockReplacement, DerelictionProfile)
  - `Behavior/Subsystems/Trigger/TriggerChecks.cs` & `TriggerSystem.cs` (Trigger conditions & execution)
  - `Behavior/Subsystems/Trigger/ActionSystem.cs` & `ActionReferenceProfile.cs` (RivalAI Actions)
  - `Events/Action/EventActionProfile.cs` & `EventActionExecution.cs` (MES Event Actions)
  - `Events/Condition/EventConditions.cs` (MES Event Conditions)
  - `Zones/Zone.cs` & `ZoneManager.cs` (Zone boundaries, persistence, and restrictions)
  - `Helpers/TagParse.cs` (List parsing and zero-stripping behavior)

### Recommended Folder Layout for Encounter Mods
```
Data/
  SpawnGroups.sbc          <-- What to spawn, where, and when (SpawnGroupDefinition)
  Behavior.sbc             <-- How the NPC acts (AI behavior tree + trigger list)
  Factions.sbc             <-- NPC faction tags and reputation
  Prefabs/                 <-- Blueprint SBC files for the actual ships/stations
  Triggers/                <-- Individual trigger + action definitions
  Replenish/               <-- Optional: ammo/item replenishment profiles
  SpawnConditions/         <-- Optional: standalone spawn condition profiles
  Loot/                    <-- Optional: loot table profiles
  Autopilot/               <-- Optional: custom autopilot profiles
```

**SubtypeId Naming Convention**: `ModName-ProfileType-DescriptiveName` (e.g. `GVK-Trigger-InsideZoneCheck-SOBAN`, `GVK-Action-SpawnDefenses-Carrier`). Standardizing this makes cross-referencing sub-profiles predictable and prevents collision across mods.

---

## 2. MES Event System vs. RivalAI Grid Trigger System

MES Events run globally via `EventManager` (server-authoritative, no physical grid needed). RivalAI Triggers run on individual in-world grids via Remote Control blocks. **They use different tag names for sub-profiles.**

| Feature | RivalAI Grid Action Tag | MES Event Action Tag | Notes |
| :--- | :--- | :--- | :--- |
| **Encounter Spawner** | `[Spawner:ProfileId]` | `[SpawnData:ProfileId]` | Using `[Spawner:]` in an Event Action causes silent failure (`Spawner.Count == 0`). |
| **Chat Message** | `[Chat:ProfileId]` | `[ChatData:ProfileId]` | Using `[Chat:]` in an Event Action fails to attach the chat profile. |
| **Counter Changes** | `[IncreaseSandboxCounters:Name]` | `[ChangeCounters:true]` + `[IncreaseCounters:Name]` | MES Event Actions **require** `[ChangeCounters:true]` gating. |
| **Zone Resizing** | `[ChangeZoneByName:true]` + `[ZoneName:]` + `[ZoneRadiusChangeType:]` + `[ZoneRadiusChangeAmount:]` + `[ChangeZoneOnlyByName:true]` | `[ChangeZoneByName:true]` + `[ZoneNames:]` + `[ZoneRadiusChangeTypes:]` + `[ZoneRadiusChangeAmounts:]` | RivalAI actions use **singular** tag names; MES Event Actions use **plural lists**. |

---

## 3. SBC XML Deserialization Quirks

### A. Strict Single `<SubtypeId>` per `<Id>` Block
Keen's XML deserializer strictly accepts **only one** `<SubtypeId>` per `<Id>` block:
```xml
<!-- INVALID: Second SubtypeId is discarded by deserializer; action fails to load -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>Trigger-OutsideZone</SubtypeId>
    <SubtypeId>Action-OutsideZone</SubtypeId>
  </Id>
  ...
</EntityComponent>

<!-- VALID: One definition per SubtypeId, each with its own <Id> block -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>Trigger-OutsideZone</SubtypeId>
  </Id>
</EntityComponent>
```
- **Symptom**: `MES / Error: Could Not Load Action Profile From Trigger: : [SubtypeId]`.

### B. Strict Single `<Id>` per `<Prefab>` / Definition Block
In prefab and block definitions using self-closing attribute tags (`<Id Type="..." Subtype="..." />`), duplicate `<Id>` elements inside a `<Prefab>` cause Keen to read the first one and discard subsequent ones:
```xml
<!-- INVALID: Deserializer reads the first Id, registering the prefab under the wrong Subtype -->
<Prefab xsi:type="MyObjectBuilder_PrefabDefinition">
  <Id Type="MyObjectBuilder_PrefabDefinition" Subtype="NST MyFaction Nav Tower" />
  <Id Type="MyObjectBuilder_PrefabDefinition" Subtype="NST Base Site Tower" />
  <CubeGrids>...</CubeGrids>
</Prefab>
```
- **Symptom**: `Spawn group initialization: Could not get prefab [SubtypeId]`.

### C. Ban XML Comments Inside `<Description>` Tags
Keen deserializes `<Description>` via `ReadElementString()`, which strictly expects plain text:
```xml
<!-- INVALID: XML comment inside <Description> -> XmlException, MOD SKIPPED -->
<Description>
  [RivalAI Behavior]
  <!-- Zone Presence Tracking -->
</Description>

<!-- VALID: Use RivalAI comment tag syntax instead -->
<Description>
  [RivalAI Behavior]
  [//Zone Presence Tracking]
</Description>
```
- **Symptom**: `System.Xml.XmlException: Unexpected node type Comment. ReadElementString method can only be called on elements with simple or empty content. MOD_CRITICAL_ERROR / MOD SKIPPED`.

---

## 4. Boolean Master-Gate Convention

Sub-configuration tags (lists of variables, targets, coordinates, amounts) **do nothing on their own** in most MES profile types: a boolean master-switch tag that defaults to `false` guards them.

> [!CAUTION]
> **The Golden Rule (MES Events only)**: Specifying child parameters (e.g. `[SetCounters:...]`, `[TrueBooleans:...]`, `[SpawnCoords:...]`) without their parent boolean tag (e.g. `[ChangeCounters:true]`, `[CheckTrueBooleans:true]`, `[SpawnEncounter:true]`) causes **silent execution failure**. MES logs zero errors, but the entire block is skipped.
>
> **RivalAI has NO master gates.** RivalAI action tags are self-gating (an empty list is a no-op), so `[SetBooleansTrue:X]` alone is valid. Do not add MES-style gates to `[MES AI Action]` profiles.

### A. MES Event Actions (`EventActionExecution.cs`)
| Master Gating Tag (Required) | Dependent Child Tags Enabled | Purpose / Effect |
| :--- | :--- | :--- |
| `[ChangeCounters:true]` | `[SetCounters:]`, `[SetCountersAmount:]`, `[IncreaseCounters:]`, `[IncreaseCountersAmount:]`, `[DecreaseCounters:]`, `[DecreaseCountersAmount:]` | Mutating Sandbox integer counters. |
| `[ChangeBooleans:true]` | `[SetBooleansTrue:]`, `[SetBooleansFalse:]` | Setting Sandbox boolean variables. |
| `[SpawnEncounter:true]` | `[SpawnCoords:]`, `[SpawnFactionTags:]`, `[SpawnData:]`, `[SpawnReplaceKeys:]`, `[SpawnReplaceValues:]` | Spawning encounters via event actions. |
| `[ChangeZoneByName:true]` | `[ZoneNames:]`, `[ZoneRadiusChangeTypes:]`, `[ZoneRadiusChangeAmounts:]` | Dynamically modifying spherical zones by name. |
| `[ChangeZoneAtPosition:true]` | `[ZoneCoords:]`, `[ZoneToggleActiveModes:]` | Activating/deactivating zones at coordinates. |
| `[ToggleEvents:true]` | `[ToggleEventIds:]`, `[ToggleEventIdModes:]`, `[ToggleEventTags:]`, `[ToggleEventTagModes:]` | Enabling or disabling other MES Events. |
| `[ResetCooldownTimeOfEvents:true]` | `[ResetEventCooldownIds:]`, `[ResetEventCooldownTags:]` | Forcing events back to 0 or full cooldown. |
| `[IncreaseRunCountOfEvents:true]` | `[IncreaseRunCountEventIds:]`, `[IncreaseRunCountEventIdAmount:]`, `[IncreaseRunCountEventTags:]` | Manually incrementing event run counters. |
| `[UseChatBroadcast:true]` | `[ChatData:]`, `[UseChatOverrideAuthor:true]`, `[ChatOverrideAuthor:]`, `[UseChatOverrideMessage:true]` | Transmitting HUD / chat notifications. |
| `[AddGPSToPlayers:true]` | `[GPSNames:]`, `[GPSDescriptions:]`, `[GPSCoords:]`, `[UseGPSObjective:true]` | Creating HUD GPS waypoints for players. |
| `[RemoveGPSFromPlayers:true]` | `[RemoveGPSNames:]` | Deleting HUD GPS waypoints from players. |

### B. MES Event Conditions (`EventConditions.cs`)
| Master Gating Tag (Required) | Dependent Child Tags Evaluated | Purpose / Effect |
| :--- | :--- | :--- |
| `[CheckCustomCounters:true]` | `[CustomCounters:]`, `[CustomCountersTargets:]`, `[CounterCompareTypes:]` | Evaluating sandbox counter variables. |
| `[CheckTrueBooleans:true]` | `[TrueBooleans:]`, `[AllowAnyTrueBoolean:true/false]` | Requiring sandbox booleans to be true. |
| `[CheckFalseBooleans:true]` | `[FalseBooleans:]`, `[AllowAnyFalseBoolean:true/false]` | Requiring sandbox booleans to be false. |
| `[CheckPlayerNear:true]` | `[PlayerNearCoords:]`, `[PlayerNearDistanceFromCoords:]`, `[PlayerNearMinDistanceFromCoords:]` | Distance checks from specified coords. |
| `[CheckPlayerCondition:true]` | `[PlayerConditionIds:]` | Player-specific state & inventory checks. |
| `[CheckThreatScore:true]` | `[ThreatScoreAmount:]`, `[ThreatScoreDistance:]`, `[ThreatScoreCoords:]`, `[ThreatScoreType:]` | Player combat grid threat checks. |

### C. RivalAI Actions & Conditions
- Grid-scoped variables (`[SetBooleansTrue]`, `[SetCounters]`) write to `StoredSettings` on the Remote Control and are visible only to that grid.
- Session-scoped variables (`[SetSandboxBooleansTrue]`, `[IncreaseSandboxCounters]`) write to world storage and are shared with MES Events and plugins.
- Token `{Faction}` works in `[SetSandboxBooleansTrue/False]` and sandbox counter tags.

---

## 5. Verified Engine & MES Bugs / Quirks

### A. Broken Action Tag - `ChangeBlocksShareModeAll`
- **[HARD]** In `ActionSystem.cs` (line 2412), the inner loop `for (int j = grid.AllTerminalBlocks.Count - 1; j >= 0; j--)` indexes `var block = grid.AllTerminalBlocks[i];` using the outer grid loop variable `i` instead of `j`.
- **Symptom**: It only ever checks index `i` repeatedly, throws `IndexOutOfRangeException` if `i >= AllTerminalBlocks.Count`, and never iterates the other terminal blocks. Do not use `ChangeBlocksShareModeAll`.

### B. `[Type:WaypointNear]` & `[Type:WaypointFar]` Crash Loops
- **[HARD]** In `TriggerChecks.cs` (lines 77, 84) and `TriggerSystem.cs` (line 205), MES indexes `_behavior.AutoPilot.State.CargoShipWaypoints[0]` without checking if `.Count > 0`.
- **Symptom**: If waypoints are empty, completed, or not a cargo ship, an unhandled `ArgumentOutOfRangeException` aborts the `ProcessTriggers` loop, silently breaking all subsequent triggers on the grid.
- **Workaround**: Use `[Type:TargetNear]` / `[Type:TargetFar]` pointing to a destination target profile instead.

### C. `[Type:InsideZone]` vs `[Type:InsideActiveZone]`
- **[HARD]** `[Type:InsideZone]` calls `ZoneManager.InsideZoneWithName(..., onlyActive: false)`. It evaluates `true` even when the target zone is deactivated!
- **Workaround**: Use `[Type:InsideActiveZone]` (and `[Type:OutsideActiveZone]`) to test only currently active zones.

### D. Voxel Cutting Tag Scope (`CutVoxelsAtAirtightCells`)
- **[HARD]** MES has **no tag named `[CutVoxels:true]`**.
  - On `[MES Spawn Conditions]`, the tag is strictly `[CutVoxelsAtAirtightCells:true]` and `[CutVoxelSize:<double>]` (`SpawnConditionsProfile.cs:739-740`). Specifying `[CutVoxels:true]` in a spawn conditions profile silently fails to register.
  - On `<SpawnGroup>`, `<CutVoxels>true</CutVoxels>` is Keen's **vanilla** SBC XML tag.

### E. Dereliction Percentage Gating (`UseSeparatePercentages`)
- **[HARD]** In `DerelictionProfile.cs` (lines 171-188), if `UseSeparatePercentages` is `false` (default), MES sets `build = value; integrity = value;`. In Space Engineers, equal build and integrity percentages render a block as unfinished construction scaffolding rather than damaged/smoking.
- Furthermore, `MinIntegrityPercentage`, `MaxIntegrityPercentage`, `MinBuildPercentage`, and `MaxBuildPercentage` are completely ignored unless `[UseSeparatePercentages:true]` is explicitly declared in the dereliction profile.

### F. Weapon Randomizer Public Definition Requirement
- **[HARD]** In `WeaponRandomizer.cs` (lines 182-194), MES iterates block definitions for weapon replacement and checks `if (!definition.Public)`. If a block definition has `<Public>false</Public>` in its SBC definition (common for hidden `_NPC` weapon variants), MES skips it UNLESS a `WeaponModRules` profile has `AllowIfNonPublic: true` or the ID is in `DefaultPublicBlocks`. Custom weapons specified in `[WeaponRandomizerTargetWhitelist:]` must have `<Public>true</Public>` or a matching mod rules override.

### G. Zone `RestrictedSpawnGroups` Blacklist & Persistence Gate
- **[HARD]** In `ZoneManager.cs` (line 320), `zone.RestrictedSpawnGroups` is **only** populated into active zone collections if `zone.Persistent == true`. Because `Persistent` defaults to `false` in `Zone.cs`, non-persistent zones completely ignore the tag.
- **[HARD]** In `SpawnGroupManager.cs` (line 191), `RestrictedZoneSpawnGroups` functions as an inverted **blacklist** (`if (collection.RestrictedZoneSpawnGroups.Contains(spawnGroup.SpawnGroupName)) continue;`), blocking matching groups rather than acting as a whitelist.

---

## 6. MES Tag Parsing Quirks & The Zero-Stripping Bug

In the MES source (`TagParse.cs`), the standard integer list parser strips all `0` values unless explicitly called with `preserveZero: true`:
```csharp
if (!preserveZero)
    result.RemoveAll(item => item == 0);
```

- **MES Event Conditions (`EventConditions.cs`)**:
  `CustomCountersTargets` calls `TagIntListCheck(s, ref CustomCountersTargets)` without preserving zeros.
  - **Symptom**: Using `[CustomCountersTargets:0]` strips the `0`, resulting in an empty targets list. Evaluation fails with `Counter Names and Targets List Counts Don't Match`.
  - **Workaround**:
    - To test `< 0` (e.g. floor clamp): Use `[CustomCountersTargets:-1]` with `[CounterCompareTypes:LessOrEqual]`.
    - To test `>= 0` (e.g. positive gate): Use `[CustomCountersTargets:-1]` with `[CounterCompareTypes:Greater]`.
- **Tags Missing `preserveZero: true`**:
  - `CustomCountersTargets` in `EventConditions.cs`
  - `CustomSandboxCountersTargets` in `ConditionReferenceProfile.cs`
  - `CustomSandboxCountersTargets` in `SpawnConditionsProfile.cs`
  - `CustomZoneCounterValue` in `ZoneConditionsProfile.cs`
  - `IncreaseCountersAmount` / `DecreaseCountersAmount` in `EventActionReference.cs`
- **Tags that Safely Preserve Zero**:
  - `SetCountersAmount` in `EventActionReference.cs` (`preserveZero: true`)
  - `CustomCountersTargets` in `ConditionReferenceProfile.cs` (RivalAI grid conditions pass `preserveZero: true`)

---

## 7. Operational Persistence & Field Rules

### A. Persistence Realities
- **Grid `CustomCounters`**: Serialized asynchronously into `RemoteControl.Storage` (`CoreBehavior.cs:514, 1567`). They do not persist across server crashes or restarts before Keen saves world data, and are lost if the Remote Control is destroyed or grid-split.
- **Session `SandboxCounters`**: Persist directly in Keen's world sandbox storage (`MyAPIGateway.Utilities.SetVariable`), surviving restarts and crashes.
- **Missing Variable Trap**: A condition referencing a sandbox counter never written to storage ALWAYS fails (`EventConditions.cs` checks the `GetVariable` success flag). Bootstrap state via a one-shot event (`UniqueEvent:true`).

### B. Combat & Physics Field Notes
- **[HARD] Turret 800m Default Clamp**: On grid spawn and weapon randomization, MES runs `SetAutomatedWeaponRanges(useMax: false)` (`GridEntity.cs:1736`), clamping all turret ranges to 800m. Action profiles must execute `[SetWeaponsToMaxRange:true]` to allow long-range weapons to engage past 800m.
- **[HARD] Suspension Controls**: MES has no suspension steering/thrust controls. Planet rovers must use hidden NPC thrusters + gyros driven by MES thrust/gyro controls.
- **[SOFT] WC2 Fixed Weapon Proxy**: In WeaponCore 2, fixed rockets, archer pods, and railguns can bug out when triggered natively by RivalAI weapon systems. Proxy them through an action profile triggering a Timer Block to fire.
- **[SOFT] Anti-Clang Aircraft Instant-Despawn**: Disabled aircraft grids should be force-despawned immediately without checking grid size (`AttemptSmallDespawn`) to prevent falling airframes from penetrating terrain meshes and locking the server into continuous Havok collision loops.
- **[SOFT] Thrust Modes**: `UseSurfaceHoverThrustMode` conflicts with `FlyLevelWithGravity` - do not enable both. Keep `WaypointTolerance` below `HoverPathStepDistance`.

---

## 8. NPC Store Grid Sales & Economy Gotchas

- **[HARD] Builder Subtype Required**: In `FactionTypes_Economy.sbc`, prefabs sold at NPC store blocks **must** be listed under a `<FactionType>` with subtype `Builder` in `<GridsForSale>`. Grids will not spawn or offer under other faction types.
- **3-Part Registration Chain**:
  1. Prefab must have a vanilla `StoreItem` definition with `<ItemType>Prefab</ItemType>`.
  2. Prefab subtype must be added to `Builder` in `FactionTypes_Economy.sbc` under `<GridsForSale>`.
  3. Prefab must be added to an MES `[MES Store]` profile under `[StoreItems:...]`.
- **[SOFT] Icons - 256x256 PNGs vs DDS**: DDS textures for prefab store previews frequently fail or corrupt. Use **256x256 PNG** files for `<Icon>` and `<TooltipImage>` (these load cleanly after the client `.sbcB5` cache is generated).
- **[HARD] Keen Store Icon Bug (Topic 49223)**: Mod-added ships in economy stores have an engine bug where icons occasionally fail to render on client store terminals.
- **[HARD] Store Block Spawn Clearance**: Store blocks enforce a strict 124m clearance radius for spawning purchased grids. Ensure physical structures and player safezones do not obstruct this radius.

---

## 9. Token Scope & Replacement Matrix (`IdsReplacer.cs`)

MES supports variable substitution through `IdsReplacer`, but token resolution depends heavily on whether execution is **grid-bound (RivalAI)** or **session-bound (MES Events)**.

### A. Supported Tokens in `IdsReplacer.cs`

| Token | Replaced With | Context Source | Supported Environments |
| :--- | :--- | :--- | :--- |
| `{Faction}` | Initial NPC faction tag (e.g. `GAALSIEN`) | `npcData.InitialFaction` | RivalAI Grid Triggers only |
| `{SpawnGroupName}` | Name of the SpawnGroup that spawned this grid | `npcData.SpawnGroupName` | RivalAI Grid Triggers only |
| `{SpawnGroupNameTruncated}` | SpawnGroup name with `_SpawnGroup` removed | `npcData.SpawnGroupName` | RivalAI Grid Triggers only |
| `{Position}` | Formatted `{X:... Y:... Z:...}` coordinates | Remote Control block position | RivalAI Grid Triggers only |
| `{EventInstance}` | Unique ID of spawning event instance | `npcData.EventInstanceId` | RivalAI Grid Triggers only |
| `{<CustomStringKey>}` | Value set by `[CustomStrings:Key,Value]` | `npcData.CustomStrings` | RivalAI Grid Triggers only |
| `{<CustomCounterKey>}`| Value of grid counter | `npcData.CustomCountersVariables` | RivalAI Grid Triggers only |
| `{<SandboxVarKey>}` | Value of session sandbox variable | `MyAPIGateway.Utilities.GetVariable` | **Both** RivalAI & MES Events |
| `{PlayerName}` | Target/detected player's name | `BroadcastSystem.cs` / `EventAction` | RivalAI Chat & MES Event Chat |
| `{GridName}` | Target/detected grid's name | `BroadcastSystem.cs` | RivalAI Chat only |
| `{PlayerRelation}` | Relation to player (`Friendly`, `Neutral`, `Enemy`) | `BroadcastSystem.cs` | RivalAI Chat only |
| `{PlayerFaction}` | Tag of player's faction | `BroadcastSystem.cs` | RivalAI Chat only |

### B. Critical Token Rules & Pitfalls
1. **[HARD] MES Events Pass `npcData = null`**: In `EventActionExecution.cs`, all calls to `IdsReplacer.ReplaceId(null, ...)` pass `null`. Therefore, `{Faction}`, `{SpawnGroupName}`, and `{<CustomStringKey>}` **never resolve in MES Events**; only `{<SandboxVarKey>}` and `{PlayerName}` (in chat) function.
2. **[HARD] Profile SubtypeIds Resolve Statically**: Trigger `[Actions:]` profile SubtypeIds are resolved at load time from `ProfileManager`. Putting tokens in action profile names (e.g. `[Actions:MyAction-{Faction}]`) **fails to find the profile**. Token replacement only runs on dynamic runtime parameters (Command codes, Zone names, GPS names, Chat text, Debug messages, LCD text, Sandbox variables).
3. **[HARD] No Rival Faction Token**: `{Faction}` always resolves to the NPC's *own* faction. There is no `{RivalFaction}` or `{OpposingFaction}` token; cross-faction interactions (e.g. deducting points from own faction and adding to rival) require separate hardcoded action profiles per faction.

---

## 10. Tooling & Diagnostics Suite

The `se-dev-mes` skill provides dedicated command-line utilities and PowerShell linters in its `scripts/` directory to inspect, validate, and scaffold MES/RivalAI mod content.

### A. Tag Inspector CLI (`query_mes_tags.py`)
Queries tag definitions, data types, and master gates directly from the local MES source code.
```bash
# Search for any tag containing 'Zone'
python scripts/query_mes_tags.py --tag Zone

# Search for tags within a specific profile type (e.g. RivalAI Action)
python scripts/query_mes_tags.py --profile "RivalAI Action" --tag Spawner
```

### B. SBC Deserialization Auditor (`audit_sbc.ps1`)
Validates XML structure against Keen deserializer pitfalls:
- Duplicate `<SubtypeId>` elements inside `<Id>` blocks.
- Duplicate `<Id>` elements inside `<Prefab>` definitions.
- Illegal XML comments (`<!-- ... -->`) inside `<Description>` tags.
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_sbc.ps1 -Path ".\Content\Data"
```

### C. MES Tag Linter (`audit_mes_tags.ps1`)
Scans `.sbc` files for semantic MES bugs and pitfall patterns:
- Zeroes in `CustomCountersTargets` (detects the zero-stripping bug).
- Crash-prone `[Type:WaypointNear]` / `[Type:WaypointFar]` triggers.
- Broken `[ChangeBlocksShareModeAll:true]` action tags.
- Missing boolean master gates in `[MES Event Action]` and `[MES Event Condition]`.
- List count mismatches across paired tags (`SetCounters` vs `SetCountersAmount`, `SpawnData` vs `SpawnCoords`).
- Dynamic tokens used in `[Actions:]` profile names or `{Faction}` inside MES Events.
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_mes_tags.ps1 -Path ".\Content\Data"
```

### D. Profile Cross-Reference Validator (`audit_mes_references.ps1`)
Validates that all profile references across files resolve cleanly:
- Remote Control -> Triggers / TriggerGroups.
- Triggers -> Conditions / Actions.
- Actions -> Spawners / Chats / CommandProfiles / Events.
- Spawners -> SpawnGroups -> Prefabs / SpawnConditions.
- Flags missing references, case mismatches, and orphaned/unused profiles.
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_mes_references.ps1 -Path ".\Content\Data" -WarnOrphans
```

### E. Profile Scaffolding Generator (`New-MesProfile.ps1`)
Generates production-ready, defensively engineered `.sbc` files for standard encounter patterns:
- `DefendedWreck`: Derelict spawn group with `[UseSeparatePercentages:true]`, proximity chat warning, damage defense-drone spawner, and timed cleanup.
- `ConvoyLeaderEscort`: CargoShip leader with follow escorts, squad combat triggers, and 800m turret range unclamp.
- `DynamicZoneLadder`: Dynamic spherical zone with counter-driven radius expansion/contraction ladder (zero-stripping safe).
- `StoreGrid`: Economy station grid registration (vanilla `StoreItem`, `Builder` subtype entry for `FactionTypes_Economy.sbc`, and `[MES Store]` profile).
```powershell
# Generate a defended wreck encounter
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern DefendedWreck -ModPrefix GVK -Name IronDrifter -Faction DERELICT

# Generate a convoy leader + escort
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern ConvoyLeaderEscort -ModPrefix GVK -Name DesertHauler -Faction GAALSIEN

# Generate a dynamic zone ladder
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern DynamicZoneLadder -ModPrefix GVK -Name ContestedTerritory

# Generate store grid economy definitions
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern StoreGrid -ModPrefix GVK -Name OutpostTrader -Faction COALITION
```
