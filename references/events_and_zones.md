# MES Events, Zones & Sandbox Persistence Reference

Architectural reference covering global MES Events, dynamic spherical/box zones, boolean master gates, and session sandbox variable persistence.

---

## 1. MES Event System Architecture

Unlike RivalAI Triggers which run locally on in-world grids via Remote Control blocks, **MES Events** run globally at the session level via `EventManager`:
- **Server-Authoritative**: Runs exclusively on dedicated servers and host machines (`IsServer`).
- **No Grid Required**: Executes even when no NPC grids exist in the world.
- **Global Coordination**: Manages server-wide progression, zone radius expansions, territory ladders, weekly schedules, and scripted campaign encounters.

### A. Tag-Name Matrix: RivalAI Grid Triggers vs. MES Event Actions
MES Events and RivalAI Grid Triggers use **different tag names** for sub-profiles and lists. Using the wrong variant silently fails:

| Feature | RivalAI Grid Action Tag | MES Event Action Tag | Notes |
| :--- | :--- | :--- | :--- |
| **Encounter Spawner** | `[Spawner:ProfileId]` | `[SpawnData:ProfileId]` | Using `[Spawner:]` in an Event Action causes silent failure (`Spawner.Count == 0`). |
| **Chat Message** | `[Chat:ProfileId]` | `[ChatData:ProfileId]` | Using `[Chat:]` in an Event Action fails to attach the chat profile. |
| **Counter Changes** | `[IncreaseSandboxCounters:Name]` | `[ChangeCounters:true]` + `[IncreaseCounters:Name]` | MES Event Actions **require** `[ChangeCounters:true]` gating. |
| **Zone Resizing** | `[ChangeZoneByName:true]` + `[ZoneName:]` + `[ZoneRadiusChangeType:]` + `[ZoneRadiusChangeAmount:]` | `[ChangeZoneByName:true]` + `[ZoneNames:]` + `[ZoneRadiusChangeTypes:]` + `[ZoneRadiusChangeAmounts:]` | RivalAI actions use **singular** tag names; MES Event Actions use **plural lists**. |

---

## 2. Boolean Master-Gate Protocol (MES Events Only)

> [!CAUTION]
> **The Golden Rule**: Sub-configuration tags inside `[MES Event Action]` and `[MES Event Condition]` **do nothing on their own**. They are guarded by boolean master gates that default to `false`.
> Omitting the master gate causes **silent failure**: MES logs no errors, but skips the action entirely.

### A. MES Event Action Master Gates (`EventActionExecution.cs`)

| Master Gating Tag (Required) | Dependent Child Tags Enabled | Purpose / Effect |
| :--- | :--- | :--- |
| `[ChangeCounters:true]` | `[SetCounters:]`, `[SetCountersAmount:]`, `[IncreaseCounters:]`, `[IncreaseCountersAmount:]`, `[DecreaseCounters:]`, `[DecreaseCountersAmount:]` | Mutating Sandbox integer counters. |
| `[ChangeBooleans:true]` | `[SetBooleansTrue:]`, `[SetBooleansFalse:]` | Setting Sandbox boolean variables. |
| `[SpawnEncounter:true]` | `[SpawnCoords:]`, `[SpawnFactionTags:]`, `[SpawnData:]`, `[SpawnReplaceKeys:]`, `[SpawnReplaceValues:]` | Spawning encounters via event actions. **[HARD]** `{Faction}` inside a `[SpawnData:]` value *does* resolve here — a bespoke, index-aligned `{Faction}` → `[SpawnFactionTags:]` replace, not `IdsReplacer` (which never runs in Events). This is the one token exception inside MES Events besides sandbox vars and chat `{PlayerName}`. See [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §5 Rule 1. |
| `[ChangeZoneByName:true]` | `[ZoneNames:]`, `[ZoneRadiusChangeTypes:]`, `[ZoneRadiusChangeAmounts:]` | Dynamically modifying spherical zones by name. |
| `[ChangeZoneAtPosition:true]` | `[ZoneCoords:]`, `[ZoneToggleActiveModes:]` | Activating/deactivating zones at coordinates. |
| `[ToggleEvents:true]` | `[ToggleEventIds:]`, `[ToggleEventIdModes:]`, `[ToggleEventTags:]`, `[ToggleEventTagModes:]` | Enabling or disabling other MES Events. **[HARD]** These same four tags also exist on `[RivalAI Action]`/`[MES AI Action]` (a different C# class, `ActionReferenceProfile.cs`). On that side they token-resolve via `IdsReplacer`; here, in `[MES Event Action]`, they don't — `EventActionExecution.cs` never wraps them. Full rundown: [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §6C. |
| `[ResetCooldownTimeOfEvents:true]` | `[ResetEventCooldownIds:]`, `[ResetEventCooldownTags:]` | Forcing events back to 0 or full cooldown. Same RivalAI-vs-Event dual-declaration/token-asymmetry as `[ToggleEvents:]` above — see [`references/profiles_and_tags.md`](references/profiles_and_tags.md) §6C. |
| `[UseChatBroadcast:true]` | `[ChatData:]`, `[UseChatOverrideAuthor:true]`, `[ChatOverrideAuthor:]`, `[UseChatOverrideMessage:true]` | Transmitting HUD / chat notifications. |
| `[AddGPSToPlayers:true]` | `[GPSNames:]`, `[GPSDescriptions:]`, `[GPSCoords:]`, `[UseGPSObjective:true]` | Creating HUD GPS waypoints for players. |
| `[RemoveGPSFromPlayers:true]` | `[RemoveGPSNames:]` | Deleting HUD GPS waypoints from players. |
| *None (Self-gated)* | `[DebugChatMessage:<Text>]`, `[DebugHudMessage:<Text>]` | Diagnostic test messages for event development (never use in production). |

### B. MES Event Condition Master Gates (`EventConditions.cs`)

| Master Gating Tag (Required) | Dependent Child Tags Evaluated | Purpose / Effect |
| :--- | :--- | :--- |
| `[CheckCustomCounters:true]` | `[CustomCounters:]`, `[CustomCountersTargets:]`, `[CounterCompareTypes:]` | Evaluating sandbox counter variables. |
| `[CheckTrueBooleans:true]` | `[TrueBooleans:]`, `[AllowAnyTrueBoolean:true/false]` | Requiring sandbox booleans to be true. |
| `[CheckFalseBooleans:true]` | `[FalseBooleans:]`, `[AllowAnyFalseBoolean:true/false]` | Requiring sandbox booleans to be false. |
| `[CheckPlayerNear:true]` | `[PlayerNearCoords:]`, `[PlayerNearDistanceFromCoords:]`, `[PlayerNearMinDistanceFromCoords:]` | Distance checks from specified coords. |
| `[CheckThreatScore:true]` | `[ThreatScoreAmount:]`, `[ThreatScoreDistance:]`, `[ThreatScoreCoords:]` | Player combat grid threat checks. |

---

## 3. The Zero-Stripping Bug & Workarounds

In `TagParse.cs`, MES strips all `0` values from integer lists unless called with `preserveZero: true`:
```csharp
if (!preserveZero)
    result.RemoveAll(item => item == 0);
```

- **[HARD] Affected Tags**:
  - `CustomCountersTargets` in `EventConditions.cs`
  - `CustomSandboxCountersTargets` in `ConditionReferenceProfile.cs`
  - `CustomSandboxCountersTargets` in `SpawnConditionsProfile.cs`
  - `CustomZoneCounterValue` in `ZoneConditionsProfile.cs`
  - `IncreaseCountersAmount` / `DecreaseCountersAmount` in `EventActionReference.cs`
- **Symptom**: Using `[CustomCountersTargets:0]` strips the `0`, resulting in an empty list. Evaluation fails with `Counter Names and Targets List Counts Don't Match`.
- **Workaround**:
  - To test `< 0` (e.g. floor clamp): Use `[CustomCountersTargets:-1]` with `[CounterCompareTypes:LessOrEqual]`.
  - To test `>= 0` (e.g. positive gate): Use `[CustomCountersTargets:-1]` with `[CounterCompareTypes:Greater]`.

---

## 4. Dynamic Zones & Progression Ladders (`[MES Zone]`)

Zones define spatial volumes that enforce territory rules, modify spawn pools, and track localized counters:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Zone-TerritoryAlpha</SubtypeId>
  </Id>
  <Description>
    [MES Zone]
    [ZoneName:ModPrefix_Zone_Alpha]
    [PublicName:Contested Territory Alpha]
    [Active:true]
    [Persistent:true]
    [Coordinates:{X:62495 Y:28019 Z:37195}]
    [Radius:25000]
  </Description>
</EntityComponent>
```

### Critical Zone Rules & Quirks:
1. **[HARD] `[Type:InsideZone]` vs `[Type:InsideActiveZone]`**:
   - `[Type:InsideZone]` calls `ZoneManager.InsideZoneWithName(..., onlyActive: false)`. It evaluates `true` even when the target zone is deactivated!
   - Always use `[Type:InsideActiveZone]` and `[Type:OutsideActiveZone]`.
2. **[HARD] Persistence Gate for `RestrictedSpawnGroups`**:
   - In `ZoneManager.cs` (line 320), `zone.RestrictedSpawnGroups` is **only** populated into active zone collections if `zone.Persistent == true`.
   - Because `Persistent` defaults to `false` in `Zone.cs`, non-persistent zones completely ignore spawn group restrictions.
3. **[HARD] Blacklist Behavior**:
   - `RestrictedZoneSpawnGroups` functions as an inverted **blacklist** (`if (collection.RestrictedZoneSpawnGroups.Contains(spawnGroup.SpawnGroupName)) continue;`), blocking matching groups rather than whitelisting them.

---

## 5. MES Event Templates & TemplateGroup

`[MES Event Template]` and `[MES Event TemplateGroup]` are a **parameterized action/condition pooling** system layered on top of the base `[MES Event]` system. They allow a single `[MES Event]` to randomly select from a pool of action variants at runtime.

### A. Three-Level Hierarchy

```
[MES Event]                     ← session-level scheduler (Phase 3)
  └─ [MES Event TemplateGroup]  ← named pool container (Phase 4)
       └─ [MES Event Template]  ← individual parameterized variant (Phase 4)
```

- **[MES Event]**: The server-authoritative scheduler. Fires on cooldown, evaluates conditions, then selects and runs one or more templates from an attached TemplateGroup.
- **[MES Event TemplateGroup]** (`TemplateEventGroup`): A named container that holds a list of Template SubtypeIds. Referenced from the Event profile by `[TemplateGroupId:<SubtypeId>]`. Registered in **Phase 4** — after Events (Phase 3) — so it can safely reference Template profiles.
- **[MES Event Template]**: A parameterized action payload. Shares the same master-gate system as `[MES Event Action]` (see §2.A). Each template is an independent profile with its own SubtypeId.

### B. Key Rules & Limits

> [!CAUTION]
> **Phase 4 registration**: `[MES Event TemplateGroup]` is registered in Phase 4, **after** `[MES Event]` (Phase 3). If a TemplateGroup SubtypeId is referenced in an Event before Phase 4 completes, the lookup returns null and the group is silently skipped. Always define TemplateGroup and Template profiles in separate `.sbc` files from the Event, or earlier in load order.

- **[HARD] `[TemplateGroupId:]` is the link**: The `[MES Event]` profile must include `[TemplateGroupId:<SubtypeId>]` pointing to a `[MES Event TemplateGroup]` profile. Without this, no template selection occurs.
- **[HARD] Template selection is random per fire**: Each time the Event fires, MES randomly selects one Template from the group's list (unless `[UseAllTemplates:true]` is set, which runs all). Order in the list is not guaranteed.
- **[HARD] Master gates apply**: Each `[MES Event Template]` uses the same `[ChangeCounters:true]`, `[SpawnEncounter:true]`, `[UseChatBroadcast:true]` master gates as `[MES Event Action]` (§2.A). Omitting a gate causes that action to silently no-op.
- **[SOFT] No cross-template state sharing**: Each template executes in isolation. There is no built-in mechanism to pass results from one template to another within a single Event fire.
- **`[ContractBlocks:<DisplayName>]` — single-use per action/template**: Only the **first** `[ContractBlocks:]` line is parsed. A second `[ContractBlocks:]` in the same profile block silently overwrites the first, resulting in only one contract board being targeted. Use one `[ContractBlocks:]` per profile.

### C. Minimal Example

```xml
<!-- Phase 3: The Event references a TemplateGroup -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id><TypeId>Inventory</TypeId><SubtypeId>GVK-Event-RandomEncounter</SubtypeId></Id>
  <Description>
    [MES Event]
    [UseEvent:true]
    [MinCooldownMs:300000]
    [MaxCooldownMs:600000]
    [TemplateGroupId:GVK-TemplateGroup-RandomEncounters]
  </Description>
</EntityComponent>

<!-- Phase 4: TemplateGroup lists the variants -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id><TypeId>Inventory</TypeId><SubtypeId>GVK-TemplateGroup-RandomEncounters</SubtypeId></Id>
  <Description>
    [MES Event TemplateGroup]
    [Templates:GVK-Template-ScoutRaid]
    [Templates:GVK-Template-CargoAmbush]
    [Templates:GVK-Template-PatrolSweep]
  </Description>
</EntityComponent>

<!-- Phase 4: One template variant -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id><TypeId>Inventory</TypeId><SubtypeId>GVK-Template-ScoutRaid</SubtypeId></Id>
  <Description>
    [MES Event Template]
    [SpawnEncounter:true]
    [SpawnData:GVK-Spawn-ScoutRaid]
    [UseChatBroadcast:true]
    [ChatData:GVK-Chat-ScoutRaid]
  </Description>
</EntityComponent>
```
