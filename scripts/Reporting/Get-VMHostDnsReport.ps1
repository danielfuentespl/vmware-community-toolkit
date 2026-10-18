# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report ESXi DNS settings from one explicit connection.
.DESCRIPTION
Read-only query. Requires VMware.VimAutomation.Core and an existing connection.
No connection, certificate, credential or global configuration is changed.
.PARAMETER Server
One connected VIServer object. All queries explicitly target this connection.
.PARAMETER Name
ESXi host name patterns. Defaults to all hosts in the selected connection.
.EXAMPLE
./Get-VMHostDnsReport.ps1 -Server $connection -Name 'lab-*'
.NOTES
New implementation generated for this toolkit; no source script code is copied.
PowerShell 7.4+ target; see docs/TOOL-VALIDATION-MATRIX.md for limited real-lab coverage.
Other versions, minimal roles and larger inventories remain unverified.
Output can contain confidential infrastructure metadata. Protect exported files.
Records are buffered: any query/projection error emits zero success records. This uses memory proportional to inventory size.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [object] $Server,
    [ValidateNotNullOrEmpty()]
    [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
    [string[]] $Name = @('*')
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $rows = @(
        $hosts = @(Get-VMHost -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($esxi in $hosts) {
            $network = Get-VMHostNetwork -Server $Server -VMHost $esxi -ErrorAction Stop -WarningAction Stop 3>$null
            if (@($network).Count -ne 1 -or $null -eq $network) { throw 'Ambiguous host network result.' }
            [pscustomobject]@{
                VIServer = $Server.Name
                VMHost = $esxi.Name
                DnsAddress = @($network.DnsAddress)
                DomainName = $network.DomainName
                SearchDomain = @($network.SearchDomain)
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('DNS report failed. No records were emitted.'),
        'Toolkit.DnsReportFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
