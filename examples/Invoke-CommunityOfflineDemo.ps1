# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Create a fictional community demonstration without PowerCLI or network access.
.DESCRIPTION
Loads bundled VM/snapshot/ESXi output projections, compares fictional inventory captures,
runs all seven offline VCF adapters, and renders one combined portable HTML report.
VM/snapshot/ESXi fixtures demonstrate output models; they do not execute live cmdlets.
No credentials, connection objects, runtime downloads or live transport are used.
.PARAMETER OutputPath
New local HTML file in an existing trusted directory. Never overwrites. Protect real outputs
outside Git; this demonstration contains only invented data. Uses a fixed fictional capture time.
.EXAMPLE
./Invoke-CommunityOfflineDemo.ps1 -OutputPath '/private/new-community-demo.html'
.OUTPUTS
One structured result with fictional Inventory, Snapshots, EsxiAudit, Changes, VCF and Report.
.NOTES
Requires the complete toolkit tree and existing PowerShell. No PowerCLI or Pester required.
Validation is local simulation, never functional VMware validation. No CSV is written.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OutputPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$fixtures=Join-Path $root 'tests/fixtures'
$data=Get-Content (Join-Path $fixtures 'unified-report.json') -Raw | ConvertFrom-Json
$audit=Get-Content (Join-Path $fixtures 'esxi-audit-report.json') -Raw | ConvertFrom-Json
foreach ($key in @('HostSecurity','HostFirewall','HostSyslog','HostTime','HostAdvancedSettings')) {
    $data | Add-Member -NotePropertyName $key -NotePropertyValue $audit.$key
}
$vcf=[ordered]@{}
foreach ($pair in @(@('Inventory','domains'),@('Health','health'),@('Versions','managers'),@('Certificates','certificates'))) {
    $vcf[$pair[0]]=@(& (Join-Path $root "scripts/VCF/Get-VCF$($pair[0]).ps1") -Path (Join-Path $fixtures "vcf-$($pair[1])-pages.json") -SourceVersion 'fictional-unverified')
}
foreach ($pair in @(@('LifecycleStatus','lifecycle','VCFLifecycle'),@('OperationsAlerts','alerts','VCFOperationsAlerts'),@('LicensingReport','licensing','VCFLicensing'))) {
    $rows=@(& (Join-Path $root "scripts/VCF/Get-VCF$($pair[0]).ps1") -Path (Join-Path $fixtures "vcf-$($pair[1])-phase12.json") -SourceVersion 'fictional-unverified')
    $vcf[$pair[0]]=$rows
    $data | Add-Member -NotePropertyName $pair[2] -NotePropertyValue $rows
}
$before=Get-Content (Join-Path $fixtures 'inventory-before.json') -Raw | ConvertFrom-Json
$after=Get-Content (Join-Path $fixtures 'inventory-after.json') -Raw | ConvertFrom-Json
$changes=@(& (Join-Path $root 'scripts/Reporting/Compare-vSphereInventory.ps1') -Baseline $before -Current $after)
$receipt=& (Join-Path $root 'scripts/Reporting/New-vSphereHealthReport.ps1') -Data $data -OutputPath $OutputPath
[pscustomobject]@{
    Mode='FictionalOfflineDemo';Validation='Simulation';RealVmwareValidated=$false
    Inventory=@($data.VMs);Snapshots=@($data.Snapshots);EsxiAudit=$audit
    Changes=$changes;VCF=[pscustomobject]$vcf;Report=$receipt
}
