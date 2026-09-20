<#
.SYNOPSIS
    Profile snippet injector for Space Engineers MES SBC files.
.DESCRIPTION
    Safely injects a new EntityComponent definition (Trigger, Action, Condition, Spawner, Chat, etc.)
    into an existing .sbc file right before </EntityComponents> or </Definitions>, ensuring
    valid XML structure without manual cursor navigation.
.PARAMETER File
    Target .sbc file path.
.PARAMETER SubtypeId
    SubtypeId for the new profile.
.PARAMETER ProfileHeader
    Profile header string, e.g. '[RivalAI Trigger]', '[RivalAI Action]', '[RivalAI Condition]'.
.PARAMETER Tags
    Array or newline-delimited string of MES/RivalAI tags.
#>
param(
    [Parameter(Mandatory=$true)]
    [string]$File,

    [Parameter(Mandatory=$true)]
    [string]$SubtypeId,

    [Parameter(Mandatory=$true)]
    [string]$ProfileHeader,

    [Parameter(Mandatory=$true)]
    [string[]]$Tags
)

if (-not (Test-Path $File)) {
    Write-Host "[ERROR] Target file does not exist: $File" -ForegroundColor Red
    exit 1
}

$raw = [System.IO.File]::ReadAllText($File)

# Construct the new EntityComponent snippet
$tagLines = ($Tags | ForEach-Object { "        $_" }) -join "`r`n"
$snippet = @"

    <EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
      <Id>
        <TypeId>Inventory</TypeId>
        <SubtypeId>$SubtypeId</SubtypeId>
      </Id>
      <Description>
        $ProfileHeader
$tagLines
      </Description>
    </EntityComponent>
"@

# Injection logic
if ($raw -match '</EntityComponents>') {
    $updated = $raw.Replace('</EntityComponents>', "$snippet`r`n  </EntityComponents>")
} elseif ($raw -match '</Definitions>') {
    # Wrap in <EntityComponents> if not present
    $wrapped = @"
  <EntityComponents>$snippet
  </EntityComponents>
</Definitions>
"@
    $updated = $raw.Replace('</Definitions>', $wrapped)
} else {
    Write-Host "[ERROR] Could not find </EntityComponents> or </Definitions> in $File" -ForegroundColor Red
    exit 1
}

# Verify XML validity
try {
    [xml]$testDoc = $updated
    [System.IO.File]::WriteAllText($File, $updated, [System.Text.Encoding]::UTF8)
    Write-Host "[SUCCESS] Injected $SubtypeId ($ProfileHeader) into: $File" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Injected XML failed validation: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

