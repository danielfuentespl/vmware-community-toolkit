# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Experimental offline lifecycle observations from a local JSON export.
.DESCRIPTION
Reference: SDDC Manager GET /v1/domains: upgradeState and upgradeStatus counters/status.
No network, authentication, PowerCLI or infrastructure writes. All rows are buffered
and emitted only after validation. This is a strict documented subset, not a full schema.
Product-version binding and functional VCF 9.x compatibility remain unverified.
.PARAMETER Path
Literal local UTF-8 JSON file, max 16 MiB/depth 64. No symlinks, network paths,
duplicate keys, comments or trailing commas. See docs/VCF-API-MATRIX.md for envelope
requirements, pagination, missing fields and safe output. Do not pass raw error exports.
.PARAMETER SourceVersion
Required operator-provided version label, never proof of compatibility.
.INPUTS
None. Use Path explicitly.
.OUTPUTS
Buffered PSCustomObject observations with source, endpoint, version label and Unknown
assessment. Empty collections emit no rows and do not establish health or compliance.
.EXAMPLE
./Get-VCFLifecycleStatus.ps1 -Path './fictional-export.json' -SourceVersion 'fixture-only'
.NOTES
Protect real exports and results outside Git. Credentials, license keys, owner names,
links and raw error text are never projected. No VMware version functionally validated.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][Alias('LiteralPath')][ValidateNotNullOrEmpty()][string]$Path,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][ValidateScript({-not [string]::IsNullOrWhiteSpace($_)})][string]$SourceVersion
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/VCF.Analysis.psm1') -Scope Local -ErrorAction Stop
try {
    $rows=@(Invoke-VCFOfflineAnalysis -Kind Lifecycle -Path $Path -SourceVersion $SourceVersion)
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new(
        [InvalidOperationException]::new('Offline VCF lifecycle export rejected. Check the documented envelope, field types and complete pages; no records were emitted.'),
        'Toolkit.VCFLifecycleExportInvalid',[Management.Automation.ErrorCategory]::InvalidData,$null))
}
$rows
