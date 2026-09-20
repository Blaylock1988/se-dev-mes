# se-dev-mes: Space Engineers MES & RivalAI Developer Skill & Tooling Suite

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Space Engineers](https://img.shields.io/badge/Space%20Engineers-v1-blue.svg)](https://www.spaceengineersgame.com/)
[![Modular Encounters Systems](https://img.shields.io/badge/MES-v2.x-orange.svg)](https://steamcommunity.com/sharedfiles/filedetails/?id=1521905890)

A comprehensive AI agent skill, developer reference, and automated diagnostics suite for modding **Modular Encounters Systems (MES)** and **RivalAI** in Space Engineers.

This skill equips AI assistants (Antigravity, Claude Code, Cursor, Cline) and modders with verified engine constraints, syntax rules, pitfall detection, and automated scaffolding.

---

## Features

- **Source-Verified Invariants**: Every rule is classified as **`[HARD]`** (code-verified against local MES C# source and Keen binaries) or **`[SOFT]`** (field-tested operational heuristics).
- **XML Deserializer Safeguards**: Detailed prevention of Keen SBC quirks (single `<SubtypeId>` per `<Id>`, single `<Id>` per `<Prefab>`, and the critical ban on `<!-- -->` comments inside `<Description>`).
- **Boolean Master-Gate Catalog**: Comprehensive tables covering master gates for MES Event Actions, Event Conditions, and RivalAI profiles.
- **Token Scope Matrix**: Precise resolution contexts for `IdsReplacer` tokens (`{Faction}`, `{Position}`, `{PlayerName}`, etc.) across grid-bound and session-bound execution.
- **Diagnostic Toolset**:
  - `query_mes_tags.py`: CLI tool querying tag definitions, expected data types, and parent profiles directly from MES C# source.
  - `audit_sbc.ps1`: Automated XML deserialization auditor.
  - `audit_mes_tags.ps1`: Semantic tag linter checking for zero-stripping bugs, broken action tags, master gates, and list alignment.
  - `audit_mes_references.ps1`: Cross-file reference validator ensuring all referenced profiles exist and match casing.
  - `New-MesProfile.ps1`: Scaffolding generator for production-ready encounter profiles.

---

## Installation

### 1. Antigravity / Gemini CLI
Clone directly into your global skills directory:
```bash
git clone https://github.com/<your-username>/se-dev-mes.git ~/.gemini/config/skills/se-dev-mes
```

### 2. Claude Code
Clone directly into your Claude skills directory:
```bash
git clone https://github.com/<your-username>/se-dev-mes.git ~/.claude/skills/se-dev-mes
```

### 3. Per-Project / Workspace (Cursor, Cline, VS Code)
Clone into your workspace's `.skills/` directory:
```bash
git clone https://github.com/<your-username>/se-dev-mes.git .skills/se-dev-mes
```

---

## Tooling & Scripts

All tools reside in the `scripts/` directory:

### 1. Tag Inspector CLI (`query_mes_tags.py`)
Searches the local MES source code for tag names, expected data types, and line references.
```bash
# Query any tag containing 'Zone'
python scripts/query_mes_tags.py --tag Zone

# Search specifically within RivalAI Action profiles
python scripts/query_mes_tags.py --profile "RivalAI Action" --tag Spawner
```

### 2. SBC XML Deserialization Auditor (`audit_sbc.ps1`)
Checks all `.sbc` files for fatal Keen deserializer traps:
- Duplicate `<SubtypeId>` within `<Id>` blocks.
- Duplicate `<Id>` attributes inside `<Prefab>`.
- XML comments inside `<Description>` tags.
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_sbc.ps1 -Path ".\Content\Data"
```

### 3. MES Tag & Master-Gate Linter (`audit_mes_tags.ps1`)
Detects runtime pitfalls:
- Zero-stripping bug in `CustomCountersTargets` / `CustomSandboxCountersTargets`.
- Fatal `WaypointNear` / `WaypointFar` index crashes.
- Broken `ChangeBlocksShareModeAll` loop indexing.
- Omission of required boolean master gates (`[ChangeCounters:true]`, `[SpawnEncounter:true]`).
- Tag list count mismatches (`SetCounters` vs `SetCountersAmount`).
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_mes_tags.ps1 -Path ".\Content\Data"
```

### 4. Cross-Reference Validator (`audit_mes_references.ps1`)
Validates that every referenced trigger, action, condition, spawner, spawn group, and prefab exists across the mod files:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_mes_references.ps1 -Path ".\Content\Data" -WarnOrphans
```

### 5. Profile Scaffolding Generator (`New-MesProfile.ps1`)
Generates boilerplate `.sbc` files following defensive engineering patterns:
```powershell
# Defended Wreck encounter (dereliction, proximity warning, defense drone spawner, cleanup)
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern DefendedWreck -ModPrefix MYMOD -Name IronDrifter -Faction DERELICT

# Convoy Leader + Escort (CargoShip leader, escort follower with formation break, 800m range unclamp)
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern ConvoyLeaderEscort -ModPrefix MYMOD -Name DesertHauler -Faction GAALSIEN

# Dynamic Zone Ladder (persistent zone with zero-stripping-safe counter expansion ladder)
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern DynamicZoneLadder -ModPrefix MYMOD -Name ContestedZone

# Store Grid (vanilla StoreItem, Builder subtype registration, and MES Store profile)
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern StoreGrid -ModPrefix MYMOD -Name OutpostTrader -Faction COALITION
```

---

## Known MES & SE Engine Pitfalls Documented in Skill

- **Zero-Stripping Bug**: `TagParse.cs` strips `0` values from integer lists unless called with `preserveZero: true`. Using `[CustomCountersTargets:0]` produces an empty list and breaks conditions.
- **Turret 800m Clamp**: On spawn, MES clamps all automated weapon ranges to 800m unless an action executes `[SetWeaponsToMaxRange:true]`.
- **`ChangeBlocksShareModeAll`**: Loop index bug in `ActionSystem.cs:2412` can crash or fail to iterate terminal blocks.
- **`WaypointNear` / `WaypointFar`**: Unchecked index on `CargoShipWaypoints[0]` crashes the trigger loop if waypoints are empty.
- **`InsideZone` vs `InsideActiveZone`**: `[Type:InsideZone]` evaluates `true` even when the target zone is deactivated.
- **Economy Store Grids**: Purchased grids only spawn if registered under a `<FactionType>` with subtype `Builder` in `FactionTypes_Economy.sbc`.

---

## Contributing

Contributions, bug reports, and newly discovered engine quirks are welcome! Please open an issue or pull request.

---

## License

This project is licensed under the [MIT License](LICENSE).
