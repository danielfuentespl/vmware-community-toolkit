# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report configured NTP server names for selected hosts.
.DESCRIPTION
Uses Get-VMHostNtpServer; reports configuration only, not synchronization, drift or
reachability. Empty server lists are valid. No service, time or configuration is changed.
Read-only; requires VMware.VimAutomation.Core and one explicit existing connection.
No connection, credential, TLS policy or infrastructure setting is changed.
.PARAMETER Server
One connected VIServer object; every provider query explicitly supplies -Server.
.PARAMETER Name
Name wildcard filters, OR semantics. Defaults to all objects in this connection.
.EXAMPLE
./Get-VMHostNtpConfiguration.ps1 -Server $connection -Name 'lab-*'
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
        $hosts=@(Get-VMHost -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($vmHost in $hosts) {
            $id=ConvertTo-ToolkitText -Value $vmHost.Id
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $id
            $hostName=ConvertTo-ToolkitText -Value $vmHost.Name
            $ntp=@(Get-VMHostNtpServer -Server $Server -VMHost $vmHost -ErrorAction Stop -WarningAction Stop 3>$null)
            $servers=[System.Collections.Generic.List[string]]::new()
            $serverNames=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $ntp) {
                $text=ConvertTo-ToolkitText -Value $entry
                if (-not $serverNames.Add($text)) { throw 'Duplicate NTP server.' }
                $servers.Add($text)
            }
            [pscustomobject]@{
                VIServer=$Server.Name; VMHostId=$id; VMHost=$hostName
                NtpServers=$servers.ToArray(); Synchronization='NotEvaluated'
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Get-VMHostNtpConfiguration failed. No records were emitted.'),
        'Toolkit.VMHostNtpConfigurationFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
