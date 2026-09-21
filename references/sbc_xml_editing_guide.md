# Space Engineers SBC & XML Editing Guide

Technical guide to editing Space Engineers `.sbc` files safely, configuring IDE environments, protecting `<Description>` blocks, and avoiding engine deserializer traps.

---

## 1. IDE Configuration (VS Code / Cursor / Cline)

To enable syntax highlighting, validation, and auto-completion for Space Engineers `.sbc` files:

### A. File Association (`settings.json`)
Add the following to your VS Code / workspace `.vscode/settings.json`:
```json
{
  "files.associations": {
    "*.sbc": "xml",
    "*.sbcB5": "xml"
  },
  "xml.format.splitAttributes": false,
  "xml.format.joinCDATALines": false
}
```

### B. Recommended Extensions
- **XML** (Red Hat / `redhat.vscode-xml`): Provides XML schema validation, closing tag completion, and linting.
- **DotXML** or **XML Tools**: Quick formatting and tree navigation.

---

## 2. The `<Description>` Tag Protection Rule

> [!CAUTION]
> **Standard XML Formatters Break MES**:
> In standard XML formatters (like Prettier or standard XML Tools), formatting an `.sbc` file will wrap or re-indent text inside `<Description>`.
> Because MES relies on clean line-by-line parsing of square-bracket tags (e.g. `[RivalAI Behavior]`), wrapping tags onto single lines or inserting indentation inside tag strings causes **parsing failure**.
>
> **The Rule**: Never run a blind global XML formatter on `.sbc` files. Always use the dedicated formatter `powershell scripts/Format-MesSbc.ps1`, which strictly isolates and protects `<Description>` content.

---

## 3. Ban on XML Comments Inside `<Description>`

Keen's XML deserializer reads `<Description>` elements using `XmlReader.ReadElementString()`. This method expects strictly plain text content.

```xml
<!-- FATAL: Crashes Keen with System.Xml.XmlException, MOD SKIPPED -->
<Description>
  [RivalAI Behavior]
  <!-- Zone Presence Tracking -->
  [BehaviorName:Passive]
</Description>

<!-- SAFE: Uses RivalAI comment tag syntax -->
<Description>
  [RivalAI Behavior]
  [//Zone Presence Tracking]
  [BehaviorName:Passive]
</Description>
```

- Any XML comment (`<!-- ... -->`) placed inside a `<Description>` tag causes Keen to throw `MOD_CRITICAL_ERROR` and abort loading the entire mod.
- Outside `<Description>`, standard XML comments are completely legal.
- Inside `<Description>`, always use `[//Comment]` syntax.

---

## 4. Encoding & BOM Integrity

- **Required Encoding**: **UTF-8** (without BOM or with standard UTF-8 BOM).
- **Avoid UTF-16**: Never save `.sbc` files in UTF-16 (Unicode in Windows Notepad), as Keen's deserializer will fail to read the root element.
- When generating or saving files via scripts, always specify `[System.Text.Encoding]::UTF8`.
- **Enforced by `audit_sbc.ps1` (Check 0)**: flags UTF-16 LE/BE BOMs and invalid UTF-8 byte sequences as critical errors. UTF-8 with or without BOM is accepted.

---

## 5. SubtypeId & Tag Casing Best Practices

- **Strict Case Sensitivity**: While NTFS is case-insensitive on Windows, Keen's internal dictionaries (`Dictionary<string, ...>`) and MES lookups are **case-sensitive** for profile SubtypeIds.
- **Prefix Standard**: Always use `ModPrefix-ProfileType-Name` (e.g. `GVK-Trigger-Damage-Cruiser`).
- **Single SubtypeId per `<Id>`**: Never place more than one `<SubtypeId>` in an `<Id>` block.

---

## 6. Deserializer Quirk Examples

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
</EntityComponent>

<!-- VALID: One definition per SubtypeId, each with its own <Id> block -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>Trigger-OutsideZone</SubtypeId>
  </Id>
</EntityComponent>
```

### B. Strict Single `<Id>` per `<Prefab>` Block
Duplicate `<Id>` elements inside a `<Prefab>` cause Keen to read the first one and discard subsequent ones:
```xml
<!-- INVALID: Deserializer reads the first Id, registering prefab under wrong Subtype -->
<Prefab xsi:type="MyObjectBuilder_PrefabDefinition">
  <Id Type="MyObjectBuilder_PrefabDefinition" Subtype="NST Nav Tower" />
  <Id Type="MyObjectBuilder_PrefabDefinition" Subtype="NST Base Site Tower" />
  <CubeGrids>...</CubeGrids>
</Prefab>
```
Both are enforced by `audit_sbc.ps1` (Check 3, XML DOM duplicate detection).

