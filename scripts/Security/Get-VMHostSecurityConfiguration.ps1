# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report lockdown and host-service configuration without judging compliance.
.DESCRIPTION
Lockdown uses Config.LockdownMode, never the obsolete adminDisabled fallback.
Service keys/policies are observations; no SSH key names or hardening baseline is assumed.
Read-only; requires existing VMware.VimAutomation.Core and one explicit connection.
No connections, refresh tasks, writes, credential persistence or TLS changes.
.PARAMETER Server
One connected VIServer; every query is explicitly scoped with Server.
.PARAMETER Name
Host name wildcard filters; defaults to all visible hosts.
.INPUTS
None. Supply parameters explicitly.
.OUTPUTS
PSCustomObject observations buffered until all queries/projections succeed.
.EXAMPLE
./Get-VMHostSecurityConfiguration.ps1 -Server $connection -Name 'esxi*.example.invalid'
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
    [string[]]$Name=@('*')
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
            $views=@(Get-View -Server $Server -Id $id -Property Config.LockdownMode -ErrorAction Stop -WarningAction Stop 3>$null)
            if ($views.Count -ne 1 -or $views[0].MoRef.Type -ne 'HostSystem') { throw 'Expected one host view.' }
            $mode=ConvertTo-ToolkitText (Get-ReportValue (Get-ReportValue $views[0] Config) LockdownMode) -Optional
            if ($mode -cnotin @('lockdownDisabled','lockdownNormal','lockdownStrict')) { $mode='Unknown' }
            $services=@(Get-VMHostService -Server $Server -VMHost $vmHost -ErrorAction Stop -WarningAction Stop 3>$null)
            if (-not $services.Count) {
                [pscustomobject]@{VIServer=$Server.Name;VMHostId=$id;VMHost=$hostName;LockdownMode=$mode;ServiceKey='Unknown';ServiceRunning='Unknown';ServicePolicy='Unknown';Assessment='NotEvaluated'}
            }
            $keys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($service in $services) {
                $key=ConvertTo-ToolkitText $service.Key
                Assert-ToolkitUniqueIdentity -Seen $keys -Id $key
                [pscustomobject]@{
                    VIServer=$Server.Name;VMHostId=$id;VMHost=$hostName;LockdownMode=$mode;ServiceKey=$key
                    ServiceRunning=ConvertTo-AuditBoolean (Get-ReportValue $service Running)
                    ServicePolicy=ConvertTo-ToolkitText (Get-ReportValue $service Policy) -Optional
                    Assessment='NotEvaluated'
                }
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new(
        [InvalidOperationException]::new('Get-VMHostSecurityConfiguration failed. No records were emitted.'),
        'Toolkit.VMHostSecurityConfigurationFailed',[Management.Automation.ErrorCategory]::ReadError,$null))
}
$rows
