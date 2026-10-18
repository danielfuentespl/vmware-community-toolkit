# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Return structured snapshot data from one explicit connection.
.DESCRIPTION
Read-only query. Requires VMware.VimAutomation.Core and an existing connection.
No connection, certificate, credential or global configuration is changed.
.PARAMETER Server
One connected VIServer object. All queries explicitly target this connection.
.PARAMETER IncludeIdentity
Add validated VMId and SnapshotId for consumers that need stable identity.
.PARAMETER Name
VM name patterns. Defaults to all VMs in the selected connection.
.EXAMPLE
./Get-SnapshotReport.ps1 -Server $connection -Name 'lab-*'
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
        $machines = @(Get-VM -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($machine in $machines) {
            Get-Snapshot -Server $Server -VM $machine -ErrorAction Stop -WarningAction Stop 3>$null | ForEach-Object {
                if ($null -eq $_.SizeGB -or $_.SizeGB -isnot [ValueType] -or $_.SizeGB -is [bool] -or -not [double]::IsFinite([double] $_.SizeGB) -or $_.SizeGB -lt 0) { throw 'Snapshot size unavailable.' }
                $record = [ordered]@{
                    VIServer = $Server.Name
                    VM = $machine.Name
                    Snapshot = $_.Name
                    Created = $_.Created
                    SizeGB = $_.SizeGB
                }
                if ($IncludeIdentity) {
                    $record.VMId = ConvertTo-ToolkitText -Value $machine.Id
                    $record.SnapshotId = ConvertTo-ToolkitText -Value $_.Id
                    $record.VM = ConvertTo-ToolkitText -Value $machine.Name
                    $record.Snapshot = ConvertTo-ToolkitText -Value $_.Name
                }
                [pscustomobject] $record
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Snapshot report failed. No records were emitted; verify datastore browse permission.'),
        'Toolkit.SnapshotReportFailed', [System.Management.Automation.ErrorCategory]::ReadError, $null))
}
$rows
