# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report snapshots strictly older than a configurable elapsed-day threshold.
.DESCRIPTION
Reuses Get-SnapshotReport with identity projection; no duplicate snapshot query code.
One day is 24 elapsed hours. Future timestamps are rejected, not silently ignored.
Read-only; requires VMware.VimAutomation.Core and one explicit existing connection.
No connection, credential, TLS policy or infrastructure setting is changed.
.PARAMETER Server
One connected VIServer object; every provider query explicitly supplies -Server.
.PARAMETER Name
Name wildcard filters, OR semantics. Defaults to all objects in this connection.
.PARAMETER OlderThanDays
Finite nonnegative age threshold, default 7; equality is excluded.
.PARAMETER AsOf
Reference instant, default UTC now. Supply an offset for reproducible reports.
.PARAMETER UnspecifiedTimeZone
Explicit source zone for provider DateTime values with unspecified Kind. Ambiguous/invalid times fail.
.EXAMPLE
./Get-OldSnapshots.ps1 -Server $connection -OlderThanDays 14 -AsOf ([datetimeoffset]'2026-10-17T00:00:00Z')
.EXAMPLE
./Get-OldSnapshots.ps1 -Server $connection -Name 'lab-*'
.INPUTS
None. Parameters are supplied explicitly; pipeline input is not accepted.
.OUTPUTS
System.Management.Automation.PSCustomObject. Buffered report rows; no rows on empty inventory.
.NOTES
New local implementation, no inherited code. PowerShell 7.4+ source target.
Limited real-lab observations are documented in docs/TOOL-VALIDATION-MATRIX.md. Coverage varies
by endpoint and tool; vendor-certified compatibility is not established.
Requires visibility/read permission for queried objects; exact roles remain unverified.
Provider errors and warnings stop the report with a sanitized stable error ID.
All records are buffered; failure emits zero success records. Memory scales with input.
Output names/identities can be sensitive; never commit real exports.
See docs/POWERCLI-CONTRACTS.md for contracts, endpoint limitations and semantics.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNull()][object] $Server,
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
    [string[]] $Name = @('*'),
    [ValidateScript({ [double]::IsFinite($_) -and $_ -ge 0 -and $_ -le 365000 })][double] $OlderThanDays=7,
    [datetimeoffset] $AsOf=[datetimeoffset]::UtcNow,
    [TimeZoneInfo] $UnspecifiedTimeZone
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Snapshot.Support.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $rows = @(
        $snapshots=@(& (Join-Path $PSScriptRoot 'Get-SnapshotReport.ps1') -Server $Server -Name $Name -IncludeIdentity -ErrorAction Stop -WarningAction Stop)
        ConvertTo-ToolkitOldSnapshot -Snapshot $snapshots -OlderThanDays $OlderThanDays -AsOf $AsOf -UnspecifiedTimeZone $UnspecifiedTimeZone
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Get-OldSnapshots failed. No records were emitted.'),
        'Toolkit.OldSnapshotsFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
