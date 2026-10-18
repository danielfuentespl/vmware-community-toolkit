# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Render fictitious ESXi configuration observations without a VMware connection.
.PARAMETER OutputPath
New private local HTML file, never overwritten. Parent directory must already exist.
.EXAMPLE
./Invoke-EsxiAuditOfflineExample.ps1 -OutputPath '/private/fixture-audit.html'
.NOTES
Uses only bundled invented output fixtures; no PowerCLI import, installation or network.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputPath)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$data=Get-Content (Join-Path $root 'tests/fixtures/esxi-audit-report.json') -Raw | ConvertFrom-Json
& (Join-Path $root 'scripts/Reporting/New-vSphereHealthReport.ps1') -Data $data -OutputPath $OutputPath
