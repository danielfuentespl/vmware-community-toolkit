# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Prepare local lab evidence; optionally perform authorized read-only PowerCLI tests.
.DESCRIPTION
Default mode is local preflight only: no DNS, TLS, credentials or connections.
Connect mode must be explicitly selected with a caller-supplied in-memory credential.
Only aggregate results are persisted outside Git; raw inventory/errors stay out of evidence.
No DNS setter is invoked. The separate DNS tool is locked to WhatIf in Phase 3.
.PARAMETER EvidenceDirectory
Dedicated restricted local directory OUTSIDE this repository; symlink paths are rejected.
.PARAMETER Connect
Explicitly authorizes this invocation to probe TLS and connect to the named lab endpoint.
.PARAMETER VIServer
Exact authorized vCenter or ESXi DNS hostname, never a URL. VCenter is a compatibility alias.
.PARAMETER EndpointType
Required declaration of vCenter or ESXi for a future authorized connection; not automatic discovery.
.PARAMETER Credential
In-memory PSCredential supplied by the operator; never requested or saved by this runner.
.PARAMETER VMName
Private VM name patterns for the two VM reports; default all visible VMs.
.PARAMETER HostName
Private host name patterns for DNS reporting; default all visible hosts.
.EXAMPLE
./Invoke-ToolkitLabValidation.ps1 -EvidenceDirectory '/private/lab-evidence'
.EXAMPLE
./Invoke-ToolkitLabValidation.ps1 -EvidenceDirectory '/private/lab-evidence' -Connect -VIServer 'vc.example.invalid' -EndpointType vCenter -Credential $labCredential -VMName 'lab-*'
.NOTES
TLS uses platform chain/hostname validation and online revocation checks; no bypass.
Requires the operator to configure Session InvalidCertificateAction=Fail before Connect.
No vSphere functionality/PowerCLI version is claimed as validated by offline tests.
#>
[CmdletBinding(DefaultParameterSetName='Preflight')]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $EvidenceDirectory,
    [Parameter(Mandatory,ParameterSetName='Connect')][switch] $Connect,
    [Parameter(Mandatory,ParameterSetName='Connect')]
    [ValidateScript({ [uri]::CheckHostName($_) -eq [UriHostNameType]::Dns -and $_ -eq $_.Trim() -and $_ -notmatch '[/\\:@*?]' })]
    [Alias('VCenter')]
    [string] $VIServer,
    [Parameter(Mandatory,ParameterSetName='Connect')][ValidateSet('vCenter','ESXi')][string] $EndpointType,
    [Parameter(Mandatory,ParameterSetName='Connect')][ValidateNotNull()][pscredential] $Credential,
    [Parameter(ParameterSetName='Connect')][ValidateNotNullOrEmpty()][string[]] $VMName = @('*'),
    [Parameter(ParameterSetName='Connect')][ValidateNotNullOrEmpty()][string[]] $HostName = @('*')

)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../Private/Lab.Support.psm1') -Scope Local -ErrorAction Stop
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$evidence = [ordered]@{
    SchemaVersion = 2
    EndpointTypeDeclared = if ($Connect) { $EndpointType } else { 'NotSpecified' }
    RunId = [guid]::NewGuid().ToString('N')
    StartedUtc = [datetime]::UtcNow.ToString('o')
    Mode = 'Preflight'
    Environment = Get-ToolkitLabEnvironment
    Outcome = 'PreflightOnly'
    DependencyStatus = 'NotChecked'
    NetworkAttempted = $false
    Tls = 'NotRun'
    Tests = @()
    Disconnect = 'NotRequired'
    Stage = 'Preflight'
    FailureStage = $null
    ErrorCode = $null
}
$directory = $null
$connections = @()
$connection = $null
try {
    $evidence.DependencyStatus = if ($evidence.Environment.CoreModuleAvailable) { 'AvailableNotImported' } else { 'MissingPowerCLI' }
    $directory = Initialize-ToolkitEvidenceDirectory -Directory $EvidenceDirectory -RepositoryRoot $root
    if ($Connect) {
        # Mandatory SwitchParameter can be explicitly bound false; it must never open a connection.
        $evidence.Mode = 'AuthorizedReadOnly'
        if (-not $evidence.Environment.CoreModuleAvailable) { throw 'PowerCLI unavailable.' }
        $evidence.Stage = 'PowerCLIRequirements'
        Initialize-ToolkitPowerCli
        $evidence.DependencyStatus = 'CommandsAndTlsPolicyChecked'
        $evidence.NetworkAttempted = $true
        $evidence.Stage = 'TlsHandshake'
        $evidence.Tls = 'AttemptedNotCompleted'
        $evidence.Tls = Test-ToolkitTlsConnection -HostName $VIServer
        $evidence.Stage = 'Connect'
        $connectionWarnings = @()
        Connect-VIServer -Server $VIServer -Credential $Credential -NotDefault -ErrorAction Stop -WarningAction SilentlyContinue -WarningVariable connectionWarnings -Verbose:$false -Debug:$false -InformationAction Ignore | ForEach-Object { $connections += $_ }
        if ($connectionWarnings.Count) { throw 'Connection warning requires review.' }
        if ($connections.Count -ne 1) { throw 'Expected one connection.' }
        $connection = $connections[0]
        if ($connection.IsConnected -ne $true) { throw 'Connection not established.' }
        $evidence.Stage = 'ReadProbes'
        $cases = @(
            @{Id='VMInventory';File='Get-VMInventory.ps1';Name=$VMName},
            @{Id='SnapshotReport';File='Get-SnapshotReport.ps1';Name=$VMName},
            @{Id='HostDnsReport';File='Get-VMHostDnsReport.ps1';Name=$HostName}
        )
        foreach ($case in $cases) {
            $result = Invoke-ToolkitReadProbe -Tool (Join-Path $PSScriptRoot "../Reporting/$($case.File)") -Arguments @{Server=$connection;Name=$case.Name}
            $evidence.Tests += [pscustomobject]@{Id=$case.Id;Outcome=$result.Outcome;RecordCount=$result.RecordCount;ErrorCode=$result.ErrorCode}
        }
        $evidence.Outcome = if (@($evidence.Tests | Where-Object Outcome -EQ 'Failed').Count) { 'Failed' } else { 'ReadProbesCompleted' }
    }
} catch {
    $evidence.FailureStage = $evidence.Stage
    if ($evidence.Stage -eq 'TlsHandshake') { $evidence.Tls = 'Failed' }
    $evidence.Outcome = 'BlockedOrFailed'
    $evidence.ErrorCode = 'LabPreconditionOrConnectionFailed'
} finally {
    foreach ($opened in $connections) {
        try {
            Disconnect-VIServer -Server $opened -Confirm:$false -ErrorAction Stop -WarningAction Stop 3>$null -Verbose:$false -Debug:$false -InformationAction Ignore | Out-Null
            if ($evidence.Disconnect -ne 'Failed') { $evidence.Disconnect = 'Completed' }
        } catch {
            $evidence.FailureStage = 'Disconnect'
            $evidence.Disconnect = 'Failed'
            $evidence.Outcome = 'Failed'
            $evidence.ErrorCode = 'DisconnectFailed'
        }
    }
}
if ($null -eq $directory) {
    throw 'Cannot prepare a restricted evidence directory outside Git; no evidence was written.'
}
$evidence.CompletedUtc = [datetime]::UtcNow.ToString('o')
try {
    $evidence.EvidenceFile = Save-ToolkitLabEvidence -Evidence $evidence -Directory $directory
} catch {
    throw 'Unable to write lab evidence; no successful run can be claimed.'
}
# Never print caller inputs, credentials, raw provider errors or report records.
[pscustomobject]@{RunId=$evidence.RunId;Outcome=$evidence.Outcome;EvidenceFile=$evidence.EvidenceFile;Mode=$evidence.Mode;DependencyStatus=$evidence.DependencyStatus}
if ($evidence.Outcome -in @('Failed','BlockedOrFailed')) {
    throw 'Lab validation did not complete successfully. Inspect the sanitized evidence outcome.'
}
