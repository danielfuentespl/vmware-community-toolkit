# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report the five documented syslog advanced settings through the shared selector.
.DESCRIPTION
Reuses Get-VMHostAdvancedSettings. Blank reported logHost means no configured remote
forwarding destination, not a vulnerability verdict or proof of log delivery.
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
./Get-VMHostSyslogConfiguration.ps1 -Server $connection -Name 'esxi*.example.invalid'
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
        $keys=@('Syslog.global.logHost','Syslog.global.logDir','Syslog.global.logDirUnique','Syslog.global.defaultRotate','Syslog.global.defaultSize')
        $settings=@(& (Join-Path $PSScriptRoot '../Security/Get-VMHostAdvancedSettings.ps1') -Server $Server -Name $Name -SettingName $keys -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($setting in $settings) {
            [pscustomobject]@{
                VIServer=$setting.VIServer;VMHostId=$setting.VMHostId;VMHost=$setting.VMHost
                SettingName=$setting.SettingName;SettingType=$setting.SettingType
                Value=$setting.Value;ValueState=$setting.ValueState;Assessment='NotEvaluated';DeliveryVerified=$false
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new(
        [InvalidOperationException]::new('Get-VMHostSyslogConfiguration failed. No records were emitted.'),
        'Toolkit.VMHostSyslogConfigurationFailed',[Management.Automation.ErrorCategory]::ReadError,$null))
}
$rows
