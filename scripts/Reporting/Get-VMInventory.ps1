# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Return structured VM inventory from one explicit connection.
.DESCRIPTION
Read-only query. Requires VMware.VimAutomation.Core and an existing connection.
No connection, certificate, credential or global configuration is changed.
.PARAMETER Server
One connected VIServer object. All queries explicitly target this connection.
.PARAMETER IncludeIdentity
Add validated VMId for scoped offline comparison; default output is unchanged.
.PARAMETER Name
VM name patterns. Defaults to all VMs in the selected connection.
.EXAMPLE
./Get-VMInventory.ps1 -Server $connection -Name 'lab-*'
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
    [string[]] $Name = @('*'),
    [switch] $IncludeIdentity
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $rows = @(
        Get-VM -Server $Server -Name $Name -ErrorAction Stop | ForEach-Object {
            if ([string]::IsNullOrWhiteSpace($_.Name) -or
                $null -eq $_.NumCpu -or $_.NumCpu -isnot [ValueType] -or $_.NumCpu -is [bool] -or
                -not [double]::IsFinite([double] $_.NumCpu) -or $_.NumCpu -lt 1 -or $_.NumCpu % 1 -ne 0 -or
                $null -eq $_.MemoryGB -or $_.MemoryGB -isnot [ValueType] -or $_.MemoryGB -is [bool] -or
                -not [double]::IsFinite([double] $_.MemoryGB) -or $_.MemoryGB -le 0) { throw 'Incomplete VM measurement.' }
            $record = [ordered]@{
                VIServer = $Server.Name
                VM = $_.Name
                PowerState = [string] $_.PowerState
                NumCpu = $_.NumCpu
                MemoryGB = $_.MemoryGB
                VMHost = [string] $_.VMHost
            }
            if ($IncludeIdentity) { $record.VMId = ConvertTo-ToolkitText -Value $_.Id }
            [pscustomobject]$record
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('VM inventory failed. No records were emitted.'),
        'Toolkit.InventoryFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
