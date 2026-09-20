# Versioning & Release Policy for se-dev-mes

This project follows **Semantic Versioning 2.0.0** (`MAJOR.MINOR.PATCH`). 

To ensure consistency across human developers and AI coding agents, all future releases and tag updates must adhere to the rules outlined in this document.

---

## 1. Version Number Criteria

### A. PATCH (`1.0.0` ➔ `1.0.1`) — Bug Fixes & Documentation Polish
Bump the **Patch** number for backward-compatible bug fixes, linter corrections, and documentation polish.

**Qualifying changes:**
- Bug fixes or false-positive corrections in PowerShell scripts (`scripts/audit_sbc.ps1`, `scripts/audit_mes_tags.ps1`, `scripts/New-MesProfile.ps1`).
- Adding newly discovered error signatures or engine bugs to `references/diagnostics_and_troubleshooting.md`.
- Correcting typos, broken markdown links, or formatting glitches across `references/` and `README.md`.
- Minor clarifications or updates to existing reference guides without adding new tools or profiles.

---

### B. MINOR (`1.0.0` ➔ `1.1.0`) — New Features & Expanded Coverage (Backward-Compatible)
Bump the **Minor** number when adding new capabilities, expanding the MES tag database, or introducing new reference guides without breaking existing workflows or CLI interfaces.

**Qualifying changes:**
- **MES Upstream Updates**: Rebuilding the offline tag database (`scripts/mes_tag_cache.json`) to track newly released MES tags or profiles from upstream MES updates.
- **New Scaffolding Archetypes**: Adding new archetype templates to `scripts/New-MesProfile.ps1` (e.g., `-Archetype CarrierFleet`).
- **New Linter Checks**: Introducing new audit checks to `scripts/audit_mes_tags.ps1` or `scripts/audit_sbc.ps1`.
- **New Reference Guides**: Adding comprehensive guides for additional third-party mods (e.g., `references/water_mod_integration.md`).
- **New Diagnostic Commands or Tools**: Adding new helper utilities or CLI options to the `scripts/` suite.

---

### C. MAJOR (`1.0.0` ➔ `2.0.0`) — Breaking Changes
Bump the **Major** number when changes break existing workflows, CLI command signatures, or repository structure.

**Qualifying changes:**
- **Breaking Script CLI Changes**: Renaming or removing command-line parameters in `New-MesProfile.ps1`, `audit_sbc.ps1`, or `audit_mes_tags.ps1` that break existing automated scripts or user workflows.
- **Repository Restructuring**: Moving or renaming core reference files in `references/` or `scripts/` that external AI agents or git submodules rely upon at fixed paths.
- **Major MES Schema Overhaul**: If Keen Software House or Modular Encounters Systems introduces an incompatible, non-backward-compatible profile format or XML structure requiring complete rewrites of user profiles.

---

## 2. Release & Tagging Checklist

Whenever a release is cut, follow these steps sequentially:

1. **Pre-Flight Validation**:
   Run the 1-step updater to verify that all XML definitions pass deserialization and semantic checks:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/Update-MesSkill.ps1
   ```
   *Do not proceed if any errors or warnings are flagged.*

2. **Commit Changes**:
   Stage and commit modified files using conventional commit messages:
   ```bash
   git add -A
   git commit -m "fix: resolve sbcB5 cache invalidation in troubleshooting guide"
   # or
   git commit -m "feat: add water mod integration reference guide"
   ```

3. **Tag the Release**:
   Create an annotated Git tag matching the new version:
   ```bash
   git tag -a v1.0.1 -m "v1.0.1 - Bug fixes and troubleshooting guide expansion"
   ```

4. **Push Commit and Tag**:
   ```bash
   git push origin main --tags
   ```

5. **Publish GitHub Release**:
   Use the GitHub CLI (`gh`) to publish the release with structured release notes:
   ```powershell
   & "C:\Program Files\GitHub CLI\gh.exe" release create v1.0.1 `
     --title "v1.0.1 — Troubleshooting Expansion & Diagnostics Fixes" `
     --notes-file "path/to/release_notes.md"
   ```

---

## 3. Golden Rule on Published Tags
> [!IMPORTANT]
> **Never force-push or overwrite a published tag** once public users or automated agents have cloned or downloaded it. Doing so desynchronizes local git clones and breaks package references.
> 
> If a bug or omission is discovered immediately after release, publish a **Patch bump (`v1.0.1`)** rather than moving the existing tag.
