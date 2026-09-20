<#
.SYNOPSIS
    Scaffolding generator for production-ready, defensively engineered MES and RivalAI profiles.
.DESCRIPTION
    Generates standard Space Engineers SBC XML files following all MES/RivalAI rules:
    - No XML comments inside <Description>
    - Single SubtypeId per <Id> block
    - Correct master gates for MES Events ([ChangeCounters:true], [SpawnEncounter:true], etc.)
    - Correct tag names for RivalAI ([Spawner:] vs [SpawnData:])
    - Workarounds for known engine bugs (800m turret clamp, zero-stripping in counter targets)
    
    Supported Patterns:
    1. DefendedWreck: Derelict encounter with damage/proximity triggers, defense drone spawner, and cleanup.
    2. ConvoyLeaderEscort: Cargo ship leader with follower escorts and break-formation combat behavior.
    3. DynamicZoneLadder: Dynamic territory zone with MES Event counter-driven radius progression ladder.
    4. StoreGrid: Economy store grid setup (Prefab StoreItem, FactionTypes_Economy Builder snippet, MES Store profile).
.PARAMETER Pattern
    Pattern type: 'DefendedWreck', 'ConvoyLeaderEscort', 'DynamicZoneLadder', 'StoreGrid'.
.PARAMETER ModPrefix
    Mod prefix to prevent profile collisions (e.g. 'GVK', 'MES').
.PARAMETER Name
    Name identifier for the encounter/grid (e.g. 'IronDrifter', 'KharakConvoy').
.PARAMETER Faction
    Faction tag (e.g. 'DERELICT', 'GAALSIEN', 'COALITION').
.PARAMETER OutFile
    Target .sbc file path. Defaults to .\<ModPrefix>_<Name>_<Pattern>.sbc.
#>
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("DefendedWreck", "ConvoyLeaderEscort", "DynamicZoneLadder", "StoreGrid")]
    [string]$Pattern,

    [Parameter(Mandatory=$true)]
    [string]$ModPrefix,

    [Parameter(Mandatory=$true)]
    [string]$Name,

    [string]$Faction = "DERELICT",
    [string]$OutFile = ""
)

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $OutFile = ".\${ModPrefix}_${Name}_${Pattern}.sbc"
}

$sb = [System.Text.StringBuilder]::new()

function Append-Header($title) {
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine('<Definitions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">')
}

function Append-Footer() {
    [void]$sb.AppendLine('</Definitions>')
}

switch ($Pattern) {
    "DefendedWreck" {
        Append-Header "Defended Wreck Pattern"
        [void]$sb.AppendLine(@"
  <!-- Spawn Group Definition -->
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Group]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
        [DerelictionProfiles:${ModPrefix}-Dereliction-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-${Name}">
          <Position>
            <X>0.0</X>
            <Y>0.0</Y>
            <Z>0.0</Z>
          </Position>
          <Speed>0.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <!-- Spawn Conditions Profile -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [RivalAiSpaceSpawn:true]
        [RivalAiPlanetSpawn:true]
        [CutVoxelsAtAirtightCells:true]
        [CutVoxelSize:2.5]
        [FactionOwner:${Faction}]
      </Description>
    </EntityComponent>

    <!-- Dereliction Profile -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Dereliction-${Name}</SubtypeId>
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

    <!-- Behavior Profile -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:Passive]
        [Triggers:${ModPrefix}-Trigger-Damage-${Name}]
        [Triggers:${ModPrefix}-Trigger-Proximity-${Name}]
        [Triggers:${ModPrefix}-Trigger-Cleanup-${Name}]
      </Description>
    </EntityComponent>

    <!-- Trigger: On Damage (Spawn Drone & Unclamp Weapon Range) -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Damage-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Damage]
        [UseTrigger:true]
        [Actions:${ModPrefix}-Action-DeployDefense-${Name}]
      </Description>
    </EntityComponent>

    <!-- Action: Deploy Defense -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-DeployDefense-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SetWeaponsToMaxRange:true]
        [SpawnEncounter:true]
        [Spawner:${ModPrefix}-Spawner-DefenseDrone-${Name}]
      </Description>
    </EntityComponent>

    <!-- Spawner Profile -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Spawner-DefenseDrone-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Spawn]
        [UseSpawn:true]
        [SpawningType:CustomSpawn]
        [StartsReady:true]
        [SpawnGroups:${ModPrefix}-SpawnGroup-DefenseDrone]
        [MinDistance:100]
        [MaxDistance:300]
        [MinAltitude:30]
        [MaxAltitude:60]
      </Description>
    </EntityComponent>

    <!-- Trigger: Proximity Warning -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Proximity-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:PlayerNear]
        [UseTrigger:true]
        [PlayerNearDistance:1500]
        [Actions:${ModPrefix}-Action-ProximityWarn-${Name}]
      </Description>
    </EntityComponent>

    <!-- Action: Proximity Warning -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-ProximityWarn-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [UseChatBroadcast:true]
        [ChatData:${ModPrefix}-Chat-Warning-${Name}]
      </Description>
    </EntityComponent>

    <!-- Chat: Warning -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Chat-Warning-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Chat]
        [UseChat:true]
        [StartsReady:true]
        [MaxChats:1]
        [BroadcastRandomly:false]
        [Author:${Faction} Automated Beacon]
        [Color:Red]
        [ChatMessages:WARNING: Automated defense perimeter breached. Hostile targets will be engaged.]
        [ChatAudio:ArcHudGPSNotification2]
        [BroadcastType:Chat]
      </Description>
    </EntityComponent>

    <!-- Trigger: Timed Despawn Cleanup -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-Cleanup-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Timer]
        [UseTrigger:true]
        [MinCooldownMs:3600000]
        [MaxCooldownMs:3600001]
        [Actions:${ModPrefix}-Action-Cleanup-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-Cleanup-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [ForceDespawn:true]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "ConvoyLeaderEscort" {
        Append-Header "Convoy Leader & Escort Pattern"
        [void]$sb.AppendLine(@"
  <!-- Spawn Group: Convoy Leader -->
  <SpawnGroups>
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-Leader-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Group]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-Leader-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>15.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-Leader-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>

    <!-- Spawn Group: Convoy Escort -->
    <SpawnGroup>
      <Id>
        <TypeId>SpawnGroupDefinition</TypeId>
        <SubtypeId>${ModPrefix}-SpawnGroup-Escort-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Group]
        [SpawnConditionsProfiles:${ModPrefix}-SpawnCondition-${Name}]
      </Description>
      <IsPirate>true</IsPirate>
      <Frequency>1.0</Frequency>
      <Prefabs>
        <Prefab SubtypeId="${ModPrefix}-Prefab-Escort-${Name}">
          <Position><X>0.0</X><Y>0.0</Y><Z>0.0</Z></Position>
          <Speed>15.0</Speed>
          <Behaviour>${ModPrefix}-Behavior-Escort-${Name}</Behaviour>
        </Prefab>
      </Prefabs>
    </SpawnGroup>
  </SpawnGroups>

  <EntityComponents>
    <!-- Common Spawn Condition -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-SpawnCondition-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Spawn Conditions]
        [RivalAiAnySpawn:true]
        [FactionOwner:${Faction}]
      </Description>
    </EntityComponent>

    <!-- Leader Behavior: CargoShip + Spawns Escorts -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-Leader-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:CargoShip]
        [AutopilotData:${ModPrefix}-Autopilot-CargoShip-${Name}]
        [Triggers:${ModPrefix}-Trigger-SpawnEscorts-${Name}]
      </Description>
    </EntityComponent>

    <!-- CargoShip Autopilot -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-CargoShip-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [IdealMinSpeed:15]
        [IdealMaxSpeed:25]
        [FlyLevelWithGravity:true]
        [WaypointTolerance:50]
      </Description>
    </EntityComponent>

    <!-- Trigger: Spawn Escorts at start -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-SpawnEscorts-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:Timer]
        [UseTrigger:true]
        [StartsReady:true]
        [MaxActions:1]
        [Actions:${ModPrefix}-Action-SpawnEscorts-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-SpawnEscorts-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SpawnEncounter:true]
        [Spawner:${ModPrefix}-Spawner-Escort-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Spawner-Escort-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Spawn]
        [UseSpawn:true]
        [SpawningType:CustomSpawn]
        [StartsReady:true]
        [SpawnGroups:${ModPrefix}-SpawnGroup-Escort-${Name}]
        [MinDistance:150]
        [MaxDistance:250]
      </Description>
    </EntityComponent>

    <!-- Escort Behavior: Escort Leader, Break Formation on Combat -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Behavior-Escort-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Behavior]
        [BehaviorName:Escort]
        [AutopilotData:${ModPrefix}-Autopilot-Escort-${Name}]
        [Triggers:${ModPrefix}-Trigger-EngageCombat-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Autopilot-Escort-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Autopilot]
        [LeaderType:Owner]
        [EngageDistance:500]
        [DisengageDistance:1200]
        [BreakFormationOnTarget:true]
      </Description>
    </EntityComponent>

    <!-- Trigger: Engage Combat (Unclamp 800m Turret Range) -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Trigger-EngageCombat-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Trigger]
        [Type:TargetNear]
        [TargetDistance:1200]
        [UseTrigger:true]
        [Actions:${ModPrefix}-Action-EngageCombat-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Action-EngageCombat-${Name}</SubtypeId>
      </Id>
      <Description>
        [RivalAI Action]
        [SetWeaponsToMaxRange:true]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "DynamicZoneLadder" {
        Append-Header "Dynamic Zone Ladder Pattern"
        [void]$sb.AppendLine(@"
  <EntityComponents>
    <!-- Dynamic Zone Definition -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Zone-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Zone]
        [ZoneName:${ModPrefix}_Zone_${Name}]
        [PublicName:${ModPrefix} ${Name} Zone]
        [Active:true]
        [Persistent:true]
        [Coordinates:{X:0.0 Y:0.0 Z:0.0}]
        [Radius:20000]
      </Description>
    </EntityComponent>

    <!-- MES Event: Ladder Up on 10 Sandbox Points -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Event-LadderUp-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event]
        [UseEvent:true]
        [UniqueEvent:false]
        [MinCooldownMs:5000]
        [MaxCooldownMs:5001]
        [ConditionIds:${ModPrefix}-EventCondition-LadderUp-${Name}]
        [ActionIds:${ModPrefix}-EventAction-LadderUp-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventCondition-LadderUp-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Condition]
        [CheckCustomCounters:true]
        [CustomCounters:${ModPrefix}_${Name}_Points]
        [CustomCountersTargets:10]
        [CounterCompareTypes:GreaterOrEqual]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventAction-LadderUp-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Action]
        [ChangeZoneByName:true]
        [ZoneNames:${ModPrefix}_Zone_${Name}]
        [ZoneRadiusChangeTypes:Increase]
        [ZoneRadiusChangeAmounts:5000]
        [ChangeCounters:true]
        [DecreaseCounters:${ModPrefix}_${Name}_Points]
        [DecreaseCountersAmount:10]
      </Description>
    </EntityComponent>

    <!-- MES Event: Ladder Down on LessOrEqual -1 (Zero-Stripping Safe!) -->
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-Event-LadderDown-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event]
        [UseEvent:true]
        [UniqueEvent:false]
        [MinCooldownMs:5000]
        [MaxCooldownMs:5001]
        [ConditionIds:${ModPrefix}-EventCondition-LadderDown-${Name}]
        [ActionIds:${ModPrefix}-EventAction-LadderDown-${Name}]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventCondition-LadderDown-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Condition]
        [CheckCustomCounters:true]
        [CustomCounters:${ModPrefix}_${Name}_Points]
        [CustomCountersTargets:-1]
        [CounterCompareTypes:LessOrEqual]
      </Description>
    </EntityComponent>

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-EventAction-LadderDown-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Event Action]
        [ChangeZoneByName:true]
        [ZoneNames:${ModPrefix}_Zone_${Name}]
        [ZoneRadiusChangeTypes:Decrease]
        [ZoneRadiusChangeAmounts:5000]
        [ChangeCounters:true]
        [IncreaseCounters:${ModPrefix}_${Name}_Points]
        [IncreaseCountersAmount:10]
      </Description>
    </EntityComponent>
  </EntityComponents>
"@)
        Append-Footer
    }

    "StoreGrid" {
        Append-Header "Store Grid Pattern"
        [void]$sb.AppendLine(@"
  <!-- 1. Vanilla StoreItem Definition -->
  <StoreItems>
    <StoreItem>
      <Id>
        <TypeId>MyObjectBuilder_StoreItemDefinition</TypeId>
        <SubtypeId>${ModPrefix}-StoreItem-${Name}</SubtypeId>
      </Id>
      <ItemType>Prefab</ItemType>
      <ItemPrefabName>${ModPrefix}-Prefab-${Name}</ItemPrefabName>
      <PricePerUnit>5000000</PricePerUnit>
      <Amount>1</Amount>
    </StoreItem>
  </StoreItems>

  <!-- 2. MES Store Profile -->
  <EntityComponents>
    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>${ModPrefix}-StoreProfile-${Name}</SubtypeId>
      </Id>
      <Description>
        [MES Store]
        [StoreItems:${ModPrefix}-StoreItem-${Name}]
      </Description>
    </EntityComponent>
  </EntityComponents>

  <!-- 
    NOTE FOR FactionTypes_Economy.sbc:
    In Keen's engine, grid sales ONLY function under <FactionType> with <SubtypeId>Builder</SubtypeId>.
    Ensure the following is added to your FactionTypes_Economy.sbc:

    <FactionType>
      <Id>
        <TypeId>FactionTypeDefinition</TypeId>
        <SubtypeId>Builder</SubtypeId>
      </Id>
      <GridsForSale>
        <PrefabSubtypeId>${ModPrefix}-Prefab-${Name}</PrefabSubtypeId>
      </GridsForSale>
    </FactionType>
  -->
"@)
        Append-Footer
    }
}

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Host "Generated $Pattern profile at: $OutFile" -ForegroundColor Green

