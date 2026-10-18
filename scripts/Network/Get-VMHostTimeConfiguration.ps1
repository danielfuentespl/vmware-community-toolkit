# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Extend the existing NTP configuration report with version-optional time observations.
.DESCRIPTION
Reuses Get-VMHostNtpConfiguration for configured servers. Config.DateTimeInfo supplies
optional time-service and zone fields; reported synchronization is not independently tested.
Read-only; requires existing VMware.VimAutomation.Core and one explicit connection.
No connections, refresh tasks, writes, credential persistence or TLS changes.
.PARAMETER Server
One connected VIServer; every query is explicitly scoped with Server.
.PARAMETER Name
Host name wildcard filters; defaults to all visible hosts.
.PARAMETER UnspecifiedTimeZone
Explicit source zone for unspecified DateTime values. Ambiguous/invalid local times fail.
.INPUTS
None. Supply parameters explicitly.
.OUTPUTS
PSCustomObject observations buffered until all queries/projections succeed.
.EXAMPLE
./Get-VMHostTimeConfiguration.ps1 -Server $connection -Name 'esxi*.example.invalid'
.NOTES
New local implementation; no inherited code. PowerShell 7.4+ target, tested locally
on 7.6.7/Linux x64 with mocks and the limited real-lab coverage in docs/TOOL-VALIDATION-MATRIX.md. Missing optional data
is Unknown; permission/query/warning/projection errors fail atomically with a stable
sanitized error ID. Empty visible host inventory returns no rows, not proof of access.
No vulnerability/compliance score. Protect real metadata outside Git. See docs/ESXI-AUDIT-CONTRACTS.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNull()][object]$Server,
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
    [string[]]$Name=@('*'),
    [TimeZoneInfo]$UnspecifiedTimeZone
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Reporting.Support.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Audit.Support.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $rows=@(
        $ntp=@(& (Join-Path $PSScriptRoot 'Get-VMHostNtpConfiguration.ps1') -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($hostRow in $ntp) {
            $views=@(Get-View -Server $Server -Id $hostRow.VMHostId -Property Config.DateTimeInfo -ErrorAction Stop -WarningAction Stop 3>$null)
            if ($views.Count -ne 1 -or $views[0].MoRef.Type -ne 'HostSystem') { throw 'Expected one host view.' }
            $time=Get-ReportValue (Get-ReportValue $views[0] Config) DateTimeInfo
            $zone=Get-ReportValue $time TimeZone
            $last=Get-ReportValue $time LastSyncTime
            $instant=if ($null -ne $last) { ConvertTo-ToolkitInstant -Value $last -UnspecifiedTimeZone $UnspecifiedTimeZone } else { $null }
            [pscustomobject]@{
                VIServer=$hostRow.VIServer;VMHostId=$hostRow.VMHostId;VMHost=$hostRow.VMHost;NtpServers=$hostRow.NtpServers
                TimeZoneKey=ConvertTo-ToolkitText (Get-ReportValue $zone Key) -Optional
                GmtOffsetSeconds=ConvertTo-AuditInteger (Get-ReportValue $zone GmtOffset) -Signed
                ReportedProtocol=ConvertTo-ToolkitText (Get-ReportValue $time SystemClockProtocol) -Optional
                TimeServiceEnabled=ConvertTo-AuditBoolean (Get-ReportValue $time Enabled)
                ReportedServiceSync=ConvertTo-AuditBoolean (Get-ReportValue $time ServiceSync)
                LastSyncUtc=$instant;IndependentSyncVerified=$false;Assessment='NotEvaluated'
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new(
        [InvalidOperationException]::new('Get-VMHostTimeConfiguration failed. No records were emitted.'),
        'Toolkit.VMHostTimeConfigurationFailed',[Management.Automation.ErrorCategory]::ReadError,$null))
}
$rows
