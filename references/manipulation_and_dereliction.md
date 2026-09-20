# Grid Manipulation, Dereliction & AiEnabled Reference

Comprehensive reference for MES grid manipulation profiles, block replacement systems, weapon randomization, dereliction damage physics, and AiEnabled bot spawning.

---

## 1. Manipulation Profile Architecture (`[MES Manipulation]`)

Manipulation profiles modify NPC grids at the moment of spawning before physics or AI initialize:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Manipulation-Standard</SubtypeId>
  </Id>
  <Description>
    [MES Manipulation]
    [UseBlockReplacer:true]
    [BlockReplacementProfiles:ModPrefix-BlockReplacement-Military]
    [UseWeaponRandomizer:true]
    [WeaponRandomizerTargetWhitelist:MyObjectBuilder_LargeGatlingTurret/(null)]
    [ClearInventory:true]
    [ReplenishProfiles:ModPrefix-Replenish-StandardAmmo]
  </Description>
</EntityComponent>
```

### Key Manipulation Capabilities:
- **Block Replacer**: Swaps block subtypes (e.g. standard armor to heavy armor, or vanilla thrusters to modded variants).
- **Weapon Randomizer**: Swaps default weapons with randomized modded weapons.
- **Inventory Control**: Clears inventories, sets randomized cargo loot, or assigns replenishment profiles.
- **Hull Cosmetics**: Re-skins armor blocks (`[ArmorSkins:]`) or paints grids to faction colors.
- **Power & Thrusters**: Converts ion thrusters to atmospheric or hydrogen on planetary spawns (`[ConvertToAtmospheric:true]`, `[ConvertToHydrogen:true]`).

---

## 2. Weapon Randomizer & Public Block Constraints

MES includes an automated weapon replacement pipeline that dynamically upgrades or randomizes turret and fixed-weapon arsenals:

- `[UseWeaponRandomizer:true]`
- `[WeaponRandomizerTargetWhitelist:<TypeId>/<SubtypeId>]`: Specifies which weapon blocks on the prefab may be replaced.
- `[WeaponRandomizerTargetBlacklist:<TypeId>/<SubtypeId>]`: Excludes critical weapons from being altered.

### The `<Public>true</Public>` Requirement:
> [!CAUTION]
> **[HARD] Public Definition Gate**: In `WeaponRandomizer.cs` (lines 182–194), MES iterates block definitions in the game database and checks `if (!definition.Public)`.
> If a block definition has `<Public>false</Public>` in its SBC definition (very common for hidden `_NPC` weapon variants), MES **skips it** unless:
> 1. A `[MES Weapon Mod Rules]` profile specifies `[AllowIfNonPublic:true]`.
> 2. Or the SubtypeId is in `DefaultPublicBlocks`.
> Custom NPC weapons must have `<Public>true</Public>` in their SBC definition or an explicit weapon mod rule.

---

## 3. Dereliction & Damaged Block Rendering (`[MES Dereliction]`)

Dereliction transforms clean prefabs into battle-damaged, smoking, sparking ruins:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Dereliction-Wreck</SubtypeId>
  </Id>
  <Description>
    [MES Dereliction]
    [UseSeparatePercentages:true]
    [MinIntegrityPercentage:20]
    [MaxIntegrityPercentage:65]
    [MinBuildPercentage:10]
    [MaxBuildPercentage:45]
    [ChanceBlockDamaged:40]
  </Description>
</EntityComponent>
```

### The Separate Percentages Rule:
> [!CAUTION]
> **[HARD] The Scaffolding Trap**: In `DerelictionProfile.cs` (lines 171–188), if `[UseSeparatePercentages:true]` is omitted (it defaults to `false`), MES sets:
> `build = value; integrity = value;`
> In the Space Engineers engine, when `BuildPercentage == IntegrityPercentage`, a block renders as an **unfinished construction skeleton** rather than a damaged/smoking block!
> Furthermore, `MinIntegrityPercentage`, `MaxIntegrityPercentage`, `MinBuildPercentage`, and `MaxBuildPercentage` are completely ignored unless `[UseSeparatePercentages:true]` is explicitly declared.

---

## 4. Bot Spawning (AiEnabled Integration) (`[MES Bot Spawn]`)

MES natively integrates with the **AiEnabled** framework to spawn walking crew, security androids, and combat bots inside spawned NPC grids:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-BotSpawn-SecurityTeam</SubtypeId>
  </Id>
  <Description>
    [MES Bot Spawn]
    [BotProfiles:CombatBot_Assault]
    [BotProfiles:CombatBot_Sniper]
    [BotSpawnChance:75]
    [BotMaxQuantity:4]
    [BotRoles:Defender]
  </Description>
</EntityComponent>
```

### AiEnabled Integration Notes:
- **Grid Waypoints**: AiEnabled requires grids to have navigable corridors or walkable surfaces for bots to pathfind effectively.
- **Spawn Block Triggers**: Bot spawns can be tied to specific blocks (e.g. Cryo Chambers, Medical Rooms) or triggered when player breaches interior doors.

---

## 5. Replenishment Profiles (`[MES Replenishment]`)

For persistent encounters, long-running static stations, or roaming convoys, replenishment profiles automatically restock spent ammunition, fuel, and supplies:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Replenish-Ammunition</SubtypeId>
  </Id>
  <Description>
    [MES Replenishment]
    [RestockItems:MyObjectBuilder_AmmoMagazine/NATO_25x184mm]
    [RestockAmounts:100]
    [RestockCooldownMs:120000]
  </Description>
</EntityComponent>
```

- Prevents NPC turrets from running out of ammunition during extended sieges or player skirmishes.
- Offloads inventory management from PB scripts to performant native MES background workers.

---

## 6. ContainerTypes, Loot Tables & Inventory Injections

ContainerTypes bridge vanilla Space Engineers inventory generation with MES spawning and RivalAI runtime actions.

### A. Vanilla Foundation (`ContainerTypes.sbc`)
In Space Engineers, loot tables are defined in `<TypeId>ContainerTypeDefinition</TypeId>` inside `ContainerTypes.sbc`:

```xml
<Definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
  <ContainerTypes>
    <ContainerType CountMin="3" CountMax="4">
      <Id>
        <TypeId>ContainerTypeDefinition</TypeId>
        <SubtypeId>PersonalContainerSmall</SubtypeId>
      </Id>
      <Items>
        <Item AmountMin="1" AmountMax="5">
          <Frequency>1.0</Frequency>
          <Id>
            <TypeId>Ingot</TypeId>
            <SubtypeId>Uranium</SubtypeId>
          </Id>
        </Item>
        <Item AmountMin="1" AmountMax="10">
          <Frequency>1.0</Frequency>
          <Id>
            <TypeId>Ingot</TypeId>
            <SubtypeId>GVK_CUs</SubtypeId>
          </Id>
        </Item>
        <Item AmountMin="1" AmountMax="2">
          <Frequency>0.2</Frequency>
          <Id>
            <TypeId>Component</TypeId>
            <SubtypeId>GVK_TurboEncabulator</SubtypeId>
          </Id>
        </Item>
      </Items>
    </ContainerType>
  </ContainerTypes>
</Definitions>
```

- **`CountMin` / `CountMax`**: Governs how many distinct item types from `<Items>` are rolled for the inventory.
- **`<Frequency>`**: Relative probability weight for an item to be selected.
- **`<AmountMin>` / `<AmountMax>`**: Quantity rolled once an item is selected.
- **GVK Production Pattern**: Overriding vanilla subtypes like `PersonalContainerSmall` (used across Keen prefabs and drop pods) allows injecting server progression items (e.g. Uranium, CUs, RUs, Tech components) globally without editing dozens of prefab blueprints.

### B. MES Spawning Manipulation (`[MES Manipulation]`)
Manipulation profiles modify prefab inventories at spawn:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Manipulation-LootSetup</SubtypeId>
  </Id>
  <Description>
    [MES Manipulation]
    [ClearExistingContainerTypes:true]
    [AssignContainerTypesToAllCargo:PersonalContainerSmall]
    [UseContainerTypeAssignment:true]
    [ContainerTypeAssignBlockName:Cargo-Valuable]
    [ContainerTypeAssignSubtypeId:HighTierMilitaryLoot]
  </Description>
</EntityComponent>
```

- **`[AssignContainerTypesToAllCargo:<ContainerTypeId>]`**: Replaces the container type on all cargo blocks across the grid (randomly selects if multiple are listed). Automatically ignores decorative DLC lockers.
- **`[UseContainerTypeAssignment:true]`**: **Master Gate** for selective assignment.
- **`[ContainerTypeAssignBlockName:<TerminalName>]`** + **`[ContainerTypeAssignSubtypeId:<ContainerTypeId>]`**: Paired lists mapping block names to specific loot tables.
- **`[ContainerTypeAssignmentReference:{BlockName:ContainerTypeId}]`**: Dictionary syntax alternative.
- **`[ClearExistingContainerTypes:true]`**: Flushes pre-existing container types before applying new ones.

> [!CAUTION]
> **[HARD] Silent Failure on List Count Mismatch**: In `ManipulationProfile.cs:1566`, MES checks `this.ContainerTypeAssignBlockName.Count == this.ContainerTypeAssignSubtypeId.Count`. If the counts differ, MES **silently drops all assignments** without error or warning.

### C. Non-Cargo Block Support (`MesContainerTypeKey`)
> [!NOTE]
> **Vanilla Limitation Solved**: In vanilla SE, only `IMyCargoContainer` blocks support `ContainerType`. Cockpits, lockers, cryo pods, and assemblers ignore it.
> **MES Engine Solution**: MES uses internal mod storage (`StorageTools.MesContainerTypeKey`) to assign container types to *any* block with an inventory. During spawn (`InventoryHelper.ApplyContainerTypes()`), MES generates content for all non-cargo blocks carrying this storage key.

### D. MES Loot Profiles (`[MES Loot]`)
```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Loot-WreckSupplies</SubtypeId>
  </Id>
  <Description>
    [MES Loot]
    [ContainerTypes:PersonalContainerSmall]
    [ContainerBlockTypes:MyObjectBuilder_CargoContainer/SmallBlockSmallContainer]
    [MinBlocks:1]
    [MaxBlocks:3]
    [AppendNameToBlock:true]
    [AppendedName: [Loot]]
  </Description>
</EntityComponent>
```

- `[ContainerTypes:<SubtypeId>]`: Assigns loot tables to matching container blocks.
- `[MinBlocks:<int>]` / `[MaxBlocks:<int>]`: Limits the number of containers receiving loot.
- `[AppendNameToBlock:true]` + `[AppendedName:<string>]`: Appends a suffix to the block custom name for HUD/terminal visibility.

> [!WARNING]
> **[KNOWN BUG] Terminal Name Suffix Failure**: In current MES builds, `[AppendNameToBlock:true]` often fails to update the block's custom name in the terminal. The loot is correctly inserted into the inventory, but the visual name suffix (e.g. ` [Loot]`) is not always applied to the block. This is a known engine/MES bug to be aware of when testing.

### E. Runtime Dynamic Loot Swapping (`[RivalAI Action]`)
RivalAI can dynamically swap container loot tables via triggers during combat or encounter progression:

```xml
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>ModPrefix-Action-UnlockVaultLoot</SubtypeId>
  </Id>
  <Description>
    [MES AI Action]
    [ApplyContainerTypeToInventoryBlock:true]
    [ContainerTypeBlockNames:Vault-Safe]
    [ContainerTypeSubtypeIds:HighTierTechLoot]
  </Description>
</EntityComponent>
```

- **`[ApplyContainerTypeToInventoryBlock:true]`**: **Master Gate** for runtime container type changes.
- **`[ContainerTypeBlockNames:<TerminalName>]`** + **`[ContainerTypeSubtypeIds:<ContainerTypeId>]`**: Paired lists targeting inventory blocks when triggers execute.

