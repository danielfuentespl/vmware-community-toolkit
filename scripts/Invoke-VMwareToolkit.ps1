# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Run an allowlisted set of read-only toolkit checks using one explicit connection.
.DESCRIPTION
No login, credential handling, infrastructure changes or arbitrary script paths.
Sequential execution with invocation-local reuse and bounded retained rows. DNS writes,
VCF offline adapters, inventory comparison and general-purpose execution are excluded.
.PARAMETER ListChecks
List the fixed read-only check catalog offline; no connection or queries.
.PARAMETER ListProfiles
List profiles and their check membership offline; no connection or queries.
.PARAMETER Server
One existing connected VIServer. No connection is created or selected implicitly.
.PARAMETER EndpointType
Explicit vCenter or ESXi declaration. Direct-ESXi certificates remain unsupported.
.PARAMETER ScopeId
Caller-established opaque identity namespace. Never derive it from a reusable hostname.
.PARAMETER CheckProfile
Alias Profile. Inventory (default): VMInventory, Tools, Datastores.
Operations: VMInventory, Tools, Snapshots, OldSnapshots, Datastores, HostHealth, Dns, Ntp, Time.
Security: Certificates, HostSecurity, Firewall, Syslog, Time, AdvancedSettings.
All: all fourteen read-only checks. Mutually exclusive with Checks.
.PARAMETER Checks
Explicit allowlisted check names; overrides the default profile, no paths accepted.
.PARAMETER VMName
VM wildcard filters for inventory and snapshot checks.
.PARAMETER VMHostName
Host wildcard filters for host-scoped checks.
.PARAMETER DatastoreName
Datastore wildcard filters.
.PARAMETER RuleName
Firewall exception name wildcard filters.
.PARAMETER SettingName
Exact advanced-setting keys; default is the five reviewed syslog keys.
.PARAMETER CertificateScope
VMHost (default, selected managed hosts) or VCenter (machine SSL certificate only).
.PARAMETER OlderThanDays
Strict snapshot age threshold in elapsed days; default 7.
.PARAMETER AsOf
Evaluation instant for snapshot/certificate dates; default UTC now.
.PARAMETER UnspecifiedTimeZone
Explicit source zone when provider timestamps have unspecified Kind.
.PARAMETER MaxRowsPerCheck
Maximum rows retained for one source or derived check; default 10000.
.PARAMETER MaxTotalRows
Maximum source/derived rows retained across this invocation; default 50000.
.PARAMETER ContinueOnError
Continue independent checks after a failed check. Default stops further work.
.PARAMETER HtmlPath
Optional new local HTML file. Never overwrites. WhatIf suppresses only HTML creation;
read queries still execute. Declined HTML makes the overall outcome Incomplete.
.EXAMPLE
./Invoke-VMwareToolkit.ps1 -ListProfiles
Offline discovery without PowerCLI or a Server. Use -ListChecks for individual checks.
.INPUTS
None. Parameters are supplied explicitly.
.OUTPUTS
One structured result with Outcome, Checks, Data, Report and query/row accounting.
Check completion means local execution, never healthy/compliant or complete visibility.
.EXAMPLE
./Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId 'authorized-scope' -Profile Inventory
.EXAMPLE
./Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId 'authorized-scope' -Checks VMInventory,Tools -HtmlPath '/private/new-report.html'
.NOTES
See docs/TOOL-VALIDATION-MATRIX.md for limited real-lab observations. New real use still requires
authorized access, approved PowerCLI and normal TLS validation. No tools are installed.
Results contain infrastructure metadata: protect outside Git. See docs/CENTRAL-RUNNER.md.
#>
[CmdletBinding(DefaultParameterSetName='Profile',SupportsShouldProcess)]
param(
    [Parameter(Mandatory,ParameterSetName='ListChecks')][switch]$ListChecks,
    [Parameter(Mandatory,ParameterSetName='ListProfiles')][switch]$ListProfiles,
    [Parameter(Mandatory,ParameterSetName='Profile')][Parameter(Mandatory,ParameterSetName='Checks')][ValidateNotNull()][object]$Server,
    [Parameter(Mandatory,ParameterSetName='Profile')][Parameter(Mandatory,ParameterSetName='Checks')][ValidateSet('vCenter','ESXi')][string]$EndpointType,
    [Parameter(Mandatory,ParameterSetName='Profile')][Parameter(Mandatory,ParameterSetName='Checks')][ValidateNotNullOrEmpty()][ValidateScript({-not [string]::IsNullOrWhiteSpace($_)})][string]$ScopeId,
    [Parameter(ParameterSetName='Profile')][Alias('Profile')][ValidateSet('Inventory','Operations','Security','All')][string]$CheckProfile='Inventory',
    [Parameter(Mandatory,ParameterSetName='Checks')][ValidateNotNullOrEmpty()]
    [ValidateSet('VMInventory','Tools','Snapshots','OldSnapshots','Datastores','HostHealth','Dns','Ntp','Certificates','HostSecurity','Firewall','Syslog','Time','AdvancedSettings')][string[]]$Checks,
    [ValidateNotNullOrEmpty()][ValidateScript({-not [string]::IsNullOrWhiteSpace($_)})][string[]]$VMName=@('*'),
    [ValidateNotNullOrEmpty()][ValidateScript({-not [string]::IsNullOrWhiteSpace($_)})][string[]]$VMHostName=@('*'),
    [ValidateNotNullOrEmpty()][ValidateScript({-not [string]::IsNullOrWhiteSpace($_)})][string[]]$DatastoreName=@('*'),
    [ValidateNotNullOrEmpty()][ValidateScript({-not [string]::IsNullOrWhiteSpace($_)})][string[]]$RuleName=@('*'),
    [ValidateNotNullOrEmpty()][ValidateScript({-not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '[*?\[\]]'})][string[]]$SettingName=@('Syslog.global.logHost','Syslog.global.logDir','Syslog.global.logDirUnique','Syslog.global.defaultRotate','Syslog.global.defaultSize'),
    [ValidateSet('VMHost','VCenter')][string]$CertificateScope='VMHost',
    [ValidateScript({[double]::IsFinite($_) -and $_ -ge 0 -and $_ -le 365000})][double]$OlderThanDays=7,
    [datetimeoffset]$AsOf=[datetimeoffset]::UtcNow,[TimeZoneInfo]$UnspecifiedTimeZone,
    [ValidateRange(1,1000000)][int]$MaxRowsPerCheck=10000,
    [ValidateRange(1,1000000)][int]$MaxTotalRows=50000,
    [switch]$ContinueOnError,[ValidateNotNullOrEmpty()][string]$HtmlPath
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'Private/Runner.Support.psm1') -Scope Local -ErrorAction Stop
if ($PSCmdlet.ParameterSetName -eq 'ListChecks') { Get-ToolkitDiscovery -Kind Checks;return }
if ($PSCmdlet.ParameterSetName -eq 'ListProfiles') { Get-ToolkitDiscovery -Kind Profiles;return }
Invoke-ToolkitRun @PSBoundParameters
