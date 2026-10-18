# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report last-known VMware Tools fields for visible virtual machines.
.DESCRIPTION
Uses Get-View with a selective Guest projection. Missing optional Tools values are Unknown.
Powered-off guest information is historical; no upgrade or guest operation is performed.
Read-only; requires VMware.VimAutomation.Core and one explicit existing connection.
No connection, credential, TLS policy or infrastructure setting is changed.
.PARAMETER Server
One connected VIServer object; every provider query explicitly supplies -Server.
.PARAMETER Name
Name wildcard filters, OR semantics. Defaults to all objects in this connection.
.EXAMPLE
./Get-VMwareToolsStatus.ps1 -Server $connection -Name 'lab-*'
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
        $views = @(Get-View -Server $Server -ViewType VirtualMachine -Property Name,Guest.ToolsVersion,Guest.ToolsVersionStatus2,Guest.ToolsRunningStatus,Runtime.PowerState -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($view in $views) {
            if ($view.MoRef.Type -ne 'VirtualMachine') { throw 'Unexpected managed object type.' }
            $id = ConvertTo-ToolkitText -Value $view.MoRef.Value
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $id
            $vmName = ConvertTo-ToolkitText -Value $view.Name
            if (-not @($Name | Where-Object { $vmName -like $_ }).Count) { continue }
            $guest = Get-ToolkitProperty -InputObject $view -Name Guest -Optional
            [pscustomobject]@{
                VIServer=$Server.Name; VMId=$id; VM=$vmName
                PowerState=ConvertTo-ToolkitText -Value $view.Runtime.PowerState
                ToolsVersion=ConvertTo-ToolkitText -Value (Get-ToolkitProperty -InputObject $guest -Name ToolsVersion -Optional) -Optional
                ToolsVersionStatus=ConvertTo-ToolkitText -Value (Get-ToolkitProperty -InputObject $guest -Name ToolsVersionStatus2 -Optional) -Optional
                ToolsRunningStatus=ConvertTo-ToolkitText -Value (Get-ToolkitProperty -InputObject $guest -Name ToolsRunningStatus -Optional) -Optional
                DataSemantics='LastKnownGuestInfo'
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Get-VMwareToolsStatus failed. No records were emitted.'),
        'Toolkit.VMwareToolsStatusFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
