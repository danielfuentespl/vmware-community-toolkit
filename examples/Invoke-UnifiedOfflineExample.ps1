# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Render invented offline report fixtures and compare two invented VM inventories.
.PARAMETER OutputDirectory
Existing trusted local directory for new health.html and changes.csv. Never overwritten.
.EXAMPLE
./Invoke-UnifiedOfflineExample.ps1 -OutputDirectory '/private/offline-example'
.NOTES
No PowerCLI import or VMware connection. Inputs are fabricated, not captured infrastructure.
Each output is exclusive; the pair is not transactional. Reuse requires new filenames/directory.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixtures=Join-Path $root 'tests/fixtures'
$data=Get-Content (Join-Path $fixtures 'unified-report.json') -Raw | ConvertFrom-Json
$before=Get-Content (Join-Path $fixtures 'inventory-before.json') -Raw | ConvertFrom-Json
$after=Get-Content (Join-Path $fixtures 'inventory-after.json') -Raw | ConvertFrom-Json
$receipt=& (Join-Path $root 'scripts/Reporting/New-vSphereHealthReport.ps1') -Data $data -OutputPath (Join-Path $OutputDirectory 'health.html')
$changes=@(& (Join-Path $root 'scripts/Reporting/Compare-vSphereInventory.ps1') -Baseline $before -Current $after -CsvPath (Join-Path $OutputDirectory 'changes.csv'))
[pscustomobject]@{Mode='OfflineFixtureExample';Html=$receipt.Path;Changes=$changes.Count;RealVmwareValidated=$false}
