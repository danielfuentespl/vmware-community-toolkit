# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report datastore capacity, free space and utilization.
.DESCRIPTION
Reads Get-Datastore, preferring its API Summary.Accessible over the deprecated
PowerCLI Accessible accessor. Legacy objects without ExtensionData remain supported.
GB vendor fields are reported as GiB. An inaccessible datastore
returns Unknown capacity instead of treating stale sizes as current. Zero capacity has no percentage.
Read-only; requires VMware.VimAutomation.Core and one explicit existing connection.
No connection, credential, TLS policy or infrastructure setting is changed.
.PARAMETER Server
One connected VIServer object; every provider query explicitly supplies -Server.
.PARAMETER Name
Name wildcard filters, OR semantics. Defaults to all objects in this connection.
.EXAMPLE
./Get-DatastoreCapacity.ps1 -Server $connection -Name 'lab-*'
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
    [string[]] $Name = @('*')
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $rows = @(
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $stores=@(Get-Datastore -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($store in $stores) {
            $id=ConvertTo-ToolkitText -Value $store.Id
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $id
            $storeName=ConvertTo-ToolkitText -Value $store.Name
            $extension=Get-ToolkitProperty -InputObject $store -Name ExtensionData -Optional
            $accessible=if ($null -ne $extension) {
                $summary=Get-ToolkitProperty -InputObject $extension -Name Summary
                Get-ToolkitProperty -InputObject $summary -Name Accessible
            } else {
                Get-ToolkitProperty -InputObject $store -Name Accessible
            }
            if ($accessible -isnot [bool]) { throw 'Invalid accessibility.' }
            $capacity=$null; $free=$null; $used=$null; $percent=$null
            $status='Unknown'
            if ($accessible) {
                $capacity=ConvertTo-ToolkitMeasurement -Value $store.CapacityGB
                $free=ConvertTo-ToolkitMeasurement -Value $store.FreeSpaceGB
                if ($free -gt $capacity) { throw 'Free space exceeds capacity.' }
                $used=$capacity-$free
                if ($capacity -gt 0) { $percent=($used/$capacity)*100 }
                $status='Reported'
            }
            [pscustomobject]@{
                VIServer=$Server.Name; DatastoreId=$id; Datastore=$storeName; Accessible=$accessible
                CapacityGiB=$capacity; FreeGiB=$free; UsedGiB=$used; UsedPercent=$percent; CapacityStatus=$status
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Get-DatastoreCapacity failed. No records were emitted.'),
        'Toolkit.DatastoreCapacityFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
