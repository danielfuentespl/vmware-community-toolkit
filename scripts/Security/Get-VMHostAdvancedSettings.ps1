# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Report explicitly selected advanced-setting metadata with bounded value disclosure.
.DESCRIPTION
Exact SettingName values are required; no wildcard or unrestricted dump. Only the five
documented syslog profile values can be disclosed. Other values are Withheld and not evaluated.
Read-only; requires existing VMware.VimAutomation.Core and one explicit connection.
No connections, refresh tasks, writes, credential persistence or TLS changes.
.PARAMETER Server
One connected VIServer; every query is explicitly scoped with Server.
.PARAMETER Name
Host name wildcard filters; defaults to all visible hosts.
.PARAMETER SettingName
Required exact nonblank keys. Missing results produce Unknown, not a presumed default.
.INPUTS
None. Supply parameters explicitly.
.OUTPUTS
PSCustomObject observations buffered until all queries/projections succeed.
.EXAMPLE
./Get-VMHostAdvancedSettings.ps1 -Server $connection -Name 'esxi*.example.invalid' -SettingName Syslog.global.logHost
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
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
    [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '[*?\[\]]' })][string[]]$SettingName
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/Toolkit.Common.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Reporting.Support.psm1') -Scope Local -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Audit.Support.psm1') -Scope Local -ErrorAction Stop
Assert-ToolkitConnection -Server $Server
try {
    $requested=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($settingKey in $SettingName) {
        if (-not $requested.Add($settingKey)) { throw 'Duplicate requested setting.' }
    }
    $rows=@(
        $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $hosts=@(Get-VMHost -Server $Server -Name $Name -ErrorAction Stop -WarningAction Stop 3>$null)
        foreach ($vmHost in $hosts) {
            $id=ConvertTo-ToolkitText $vmHost.Id
            Assert-ToolkitUniqueIdentity -Seen $seen -Id $id
            $hostName=ConvertTo-ToolkitText $vmHost.Name
            $settings=@(Get-AdvancedSetting -Server $Server -Entity $vmHost -Name $SettingName -ErrorAction Stop -WarningAction Stop 3>$null)
            $map=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($setting in $settings) {
                $key=ConvertTo-ToolkitText $setting.Name
                if (-not $requested.Contains($key) -or $map.ContainsKey($key)) { throw 'Unexpected or duplicate setting.' }
                $map.Add($key,$setting)
            }
            foreach ($key in $SettingName) {
                $setting=if ($map.ContainsKey($key)) { $map[$key] } else { $null }
                $safe=Get-AuditSafeSetting -SettingName $key -Setting $setting
                [pscustomobject]@{
                    VIServer=$Server.Name;VMHostId=$id;VMHost=$hostName;SettingName=$key
                    SettingType=ConvertTo-ToolkitText (Get-ReportValue $setting Type) -Optional
                    Value=$safe.Value;ValueState=$safe.ValueState;Assessment='NotEvaluated'
                }
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([Management.Automation.ErrorRecord]::new(
        [InvalidOperationException]::new('Get-VMHostAdvancedSettings failed. No records were emitted.'),
        'Toolkit.VMHostAdvancedSettingsFailed',[Management.Automation.ErrorCategory]::ReadError,$null))
}
$rows
