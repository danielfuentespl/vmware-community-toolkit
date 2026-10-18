# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report selected ESXi firewall exceptions as configuration observations.
.DESCRIPTION
Uses Get-VMHostFirewallException. This is not the complete effective firewall policy
or an end-to-end reachability test. Allowed IP lists and default policy are not inferred.
Read-only; requires existing VMware.VimAutomation.Core and one explicit connection.
No connections, refresh tasks, writes, credential persistence or TLS changes.
.PARAMETER Server
One connected VIServer; every query is explicitly scoped with Server.
.PARAMETER Name
Host name wildcard filters; defaults to all visible hosts.
.PARAMETER RuleName
Firewall exception name wildcard filters; defaults to all exceptions.
.INPUTS
None. Supply parameters explicitly.
.OUTPUTS
PSCustomObject observations buffered until all queries/projections succeed.
.EXAMPLE
./Get-VMHostFirewallReport.ps1 -Server $connection -Name 'esxi*.example.invalid'
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
    [ValidateNotNullOrEmpty()][ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })][string[]]$RuleName=@('*')
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Reporting.Support.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Audit.Support.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $rows=@(
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $hosts=@(Get-VMHost -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($vmHost in $hosts) {
            $id=ConvertTo-ToolkitText $vmHost.Id
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $id
            $hostName=ConvertTo-ToolkitText $vmHost.Name
            $exceptions=@(Get-VMHostFirewallException -Server $Server -VMHost $vmHost -Name $RuleName -ErrorAction Stop -WarningAction Stop 3>$null)
            $rules=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            if (-not $exceptions.Count) {
                [pscustomobject]@{VIServer=$Server.Name;VMHostId=$id;VMHost=$hostName;RuleUid='Unknown';RuleName='Unknown';Enabled='Unknown';IncomingPorts='Unknown';OutgoingPorts='Unknown';Protocols='Unknown';ServiceRunning='Unknown';Observation='NoMatchingExceptions';Assessment='NotEvaluated'}
            }
            foreach ($exception in $exceptions) {
                $uid=ConvertTo-ToolkitText $exception.Uid
                Assert-ToolkitUniqueIdentity -Seen $rules -Id $uid
                [pscustomobject]@{
                    VIServer=$Server.Name;VMHostId=$id;VMHost=$hostName;RuleUid=$uid;RuleName=ConvertTo-ToolkitText $exception.Name
                    Enabled=ConvertTo-AuditBoolean (Get-ReportValue $exception Enabled)
                    IncomingPorts=ConvertTo-ToolkitText (Get-ReportValue $exception IncomingPorts) -Optional
                    OutgoingPorts=ConvertTo-ToolkitText (Get-ReportValue $exception OutgoingPorts) -Optional
                    Protocols=ConvertTo-ToolkitText (Get-ReportValue $exception Protocols) -Optional
                    ServiceRunning=ConvertTo-AuditBoolean (Get-ReportValue $exception ServiceRunning)
                    Observation='Reported';Assessment='NotEvaluated'
                }
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new(
        [InvalidOperationException]::new('Get-VMHostFirewallReport failed. No records were emitted.'),
        'Toolkit.VMHostFirewallReportFailed',[Management.Automation.ErrorCategory]::ReadError,$null))
}
$rows
