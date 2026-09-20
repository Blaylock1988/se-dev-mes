# MES Spawning Architecture & Conditions Reference

Deep-dive architectural guide to Modular Encounters Systems (MES) spawning algorithms, spawner types, environmental filters, threat calculations, and event spawning.

---

## 1. Spawner Types & Execution Pathways

MES categorizes all spawns into distinct operational streams:

| Spawner Type | Environment | Trigger Mechanism | Altitude & Placement |
| :--- | :--- | :--- | :--- |
| **Space Cargo Ship** | Space (Zero-G) | Periodic timer per active player | Spawns ~10–15km from player, travels in vector, despawns at end |
| **Planetary Cargo Ship** | Planet / Atmosphere | Periodic timer per active player | Spawns along planetary tangent at configured altitude, traverses waypoints |
| **Random Encounter** | Space | Player movement into unpopulated voxel/space sector | Static or slow-drifting wreckage/stations |
| **Planetary Installation** | Planet Surface | Player movement into unpopulated terrain sector | Voxel-aligned static bases, outposts, and towers |
| **Boss Encounter** | Space or Planet | Custom conditions, threat score, or MES Events | High-threat capital ships or fortified complexes |
| **Drone Encounter** | Space or Planet | RivalAI Trigger (`[Type:Damage]`, `[Type:PlayerNear]`) | Custom spawn around parent grid via `[RivalAI Spawn]` |
| **Event Encounter** | Space or Planet | MES Event Action (`[SpawnEncounter:true]`) | Spawned at exact coordinates or player offset |

---

## 2. Spawn Group Architecture (`<SpawnGroup>`)

A spawn group definition combines vanilla Keen tags with MES description tags:

```xml
<SpawnGroup>
  <Id>
    <TypeId>SpawnGroupDefinition</TypeId>
    <SubtypeId>ModPrefix-SpawnGroup-EncounterName</SubtypeId>
  </Id>
  <Description>
    [MES Spawn Group]
    [SpawnConditionsProfiles:ModPrefix-SpawnCondition-EncounterName]
    [DerelictionProfiles:ModPrefix-Dereliction-EncounterName]
    [ManipulationProfiles:ModPrefix-Manipulation-EncounterName]
  </Description>
  <IsPirate>true</IsPirate>
  <Frequency>5.0</Frequency>
  <Prefabs>
    <Prefab SubtypeId="ModPrefix-Prefab-EncounterName">
      <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
      <Speed>15.0</Speed>
      <Behaviour>ModPrefix-Behavior-EncounterName</Behaviour>
    </Prefab>
  </Prefabs>
</SpawnGroup>
```

### Critical Spawn Group Tags:
- `<Frequency>`: Relative weight among eligible groups in the same pool. Higher frequency increases spawn probability relative to other groups.
- `[SpawnConditionsProfiles:]`: Reference to one or more `[MES Spawn Conditions]` profiles.
- `[DerelictionProfiles:]`: Reference to dereliction profiles applying damaged block rendering.
- `[ManipulationProfiles:]`: Reference to block replacement, inventory, and weapon randomizer rules.

---

## 3. Spawn Conditions Profile (`[MES Spawn Conditions]`)

Declared in an `Inventory` EntityComponent definition.

### A. Environment & Gravity Gates
- `[SpaceCargoShip:bool]`: Enables spawning in space cargo pools.
- `[LunarCargoShip:bool]`: Enables spawning in moon cargo pools.
- `[PlanetaryCargoShip:bool]`: Enables spawning in planetary cargo pools.
- `[SpaceRandomEncounter:bool]`: Enables static space encounters.
- `[PlanetaryInstallation:bool]`: Enables planetary base/station spawns.
- `[RivalAiAnySpawn:bool]`: Master switch for custom RivalAI drone/event spawns.
- `[RivalAiSpaceSpawn:bool]` / `[RivalAiPlanetSpawn:bool]`: Environment gates for custom spawns.

### B. Planetary Altitude & Placement
- `[MinAltitude:<double>]` & `[MaxAltitude:<double>]`: Altitude range relative to terrain surface.
- `[MinPlanetSurfaceAltitude:<double>]`: Absolute distance from sea level.
- `[CutVoxelsAtAirtightCells:true]`: **[HARD]** Cuts terrain meshes only around airtight cells of subterranean stations.
- `[CutVoxelSize:<double>]`: Voxel cut buffer size in meters (e.g. `2.5`).
  > [!WARNING]
  > Never use `[CutVoxels:true]` on `[MES Spawn Conditions]`. It does not exist and silently fails. `<CutVoxels>true</CutVoxels>` is Keen's vanilla XML tag for `<SpawnGroup>`.

### C. Threat Score & Combat Readiness
MES evaluates player threat score based on block count, weapons, and grid mass in range:
- `[UseThreatLevelCheck:true]`
- `[ThreatScoreMinimum:<int>]` & `[ThreatScoreMaximum:<int>]`
- `[ThreatScoreDistance:<double>]`: Radius around spawn point to calculate player threat (default: 5000m).
- `[ThreatScoreGridConfiguration:All]` (or `Static`, `Large`, `Small`).

### D. Weather, Day/Night & Sandbox Variables
- `[WeatherRequired:true]` + `[AllowedWeatherSystems:Fog,Dust,Sandstorm]`: Requires active planet weather.
- `[RequireDay:true]` / `[RequireNight:true]`: Solar angle gates.
- `[UseSandboxBooleans:true]` + `[TrueBooleans:...]` / `[FalseBooleans:...]`.
- `[UseSandboxCounters:true]` + `[SandboxCounters:...]` + `[SandboxCountersTargets:...]` + `[SandboxCounterCompareTypes:...]`.

---

## 4. RivalAI Grid-Bound Spawner (`[RivalAI Spawn]`)

Used inside Action profiles (`[Spawner:<SubtypeId>]`) to deploy escorts, defense drones, or reinforcements around a live grid.

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Spawner-DefenseDrone</SubtypeId>
  </Id>
  <Description>
    [RivalAI Spawn]
    [UseSpawn:true]
    [SpawningType:CustomSpawn]
    [StartsReady:true]
    [SpawnGroups:ModPrefix-SpawnGroup-DefenseDrone]
    [MinDistance:150]
    [MaxDistance:300]
    [MinAltitude:30]
    [MaxAltitude:60]
    [InheritNpcAltitude:true]
  </Description>
</EntityComponent>
```

- **Required Gate**: `[UseSpawn:true]`
- `[SpawningType:CustomSpawn]`: Spawns relative to parent grid.
- `[MinDistance:<double>]` & `[MaxDistance:<double>]`: Radial distance from parent.
- `[InheritNpcAltitude:bool]`: Aligns drone altitude to parent grid's altitude.

---

## 5. MES Event Spawner (`[MES Event Action]`)

Used by global session-level events to spawn encounters at precise coordinates:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-EventAction-SpawnConvoy</SubtypeId>
  </Id>
  <Description>
    [MES Event Action]
    [SpawnEncounter:true]
    [SpawnCoords:{X:60487.11 Y:32965.06 Z:44090.29}]
    [SpawnFactionTags:GAALSIEN]
    [SpawnFactionTags:SPRT]
    [SpawnData:ModPrefix-EventSpawner-Convoy]
  </Description>
</EntityComponent>
```

### Critical Event Spawner Rules:
1. **Tag Name**: Must use `[SpawnData:<SubtypeId>]`, NOT `[Spawner:]`.
2. **Master Gate**: Must declare `[SpawnEncounter:true]`.
3. **List Alignment**: `SpawnCoords`, `SpawnFactionTags`, and `SpawnData` must have strictly identical element counts.
4. **Special Flags on Spawner Profile**:
   - `[ProcessAsAdminSpawn:true]`: Bypasses standard player distance and safezone spawn rejection.
   - `[IgnoreSafetyChecks:true]`: Allows spawning near player grids or structures for scripted set-pieces.
   - `[InheritNpcAltitude:false]`: Uses absolute coordinate altitude rather than raycasting from a non-existent parent.

