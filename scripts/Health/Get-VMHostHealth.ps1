# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report the host alarm summary and connection/maintenance state.
.DESCRIPTION
Uses a fresh selective HostSystem Get-View request. OverallStatus is alarm status, not a
hardware diagnostic, sensor scan or assurance that a disconnected host is healthy.
Read-only; requires VMware.VimAutomation.Core and one explicit existing connection.
No connection, credential, TLS policy or infrastructure setting is changed.
.PARAMETER Server
One connected VIServer object; every provider query explicitly supplies -Server.
.PARAMETER Name
Name wildcard filters, OR semantics. Defaults to all objects in this connection.
.EXAMPLE
./Get-VMHostHealth.ps1 -Server $connection -Name 'lab-*'
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
        $views = @(Get-View -Server $Server -ViewType HostSystem -Property Name,Summary.OverallStatus,Runtime.ConnectionState,Runtime.InMaintenanceMode -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($view in $views) {
            if ($view.MoRef.Type -ne 'HostSystem') { throw 'Unexpected managed object type.' }
            $id=ConvertTo-ToolkitText -Value $view.MoRef.Value
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $id
            $hostName=ConvertTo-ToolkitText -Value $view.Name
            if (-not @($Name | Where-Object { $hostName -like $_ }).Count) { continue }
            $summary=Get-ToolkitProperty -InputObject $view -Name Summary -Optional
            $reported=ConvertTo-ToolkitText -Value (Get-ToolkitProperty -InputObject $summary -Name OverallStatus -Optional) -Optional
            $alarm=if ($reported -cin @('green','yellow','red','gray')) { $reported } else { 'Unknown' }
            if ($view.Runtime.InMaintenanceMode -isnot [bool]) { throw 'Invalid maintenance state.' }
            [pscustomobject]@{
                VIServer=$Server.Name; VMHostId=$id; VMHost=$hostName
                ConnectionState=ConvertTo-ToolkitText -Value $view.Runtime.ConnectionState
                InMaintenanceMode=$view.Runtime.InMaintenanceMode
                AlarmStatus=$alarm; Assessment='AlarmSummaryOnly'; HardwareHealth='NotEvaluated'
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Get-VMHostHealth failed. No records were emitted.'),
        'Toolkit.VMHostHealthFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
