# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
function Get-ToolkitLabEnvironment {
    [CmdletBinding()]
    param()
    $PSModuleAutoLoadingPreference = 'None'
    $names = @('Connect-VIServer','Disconnect-VIServer','Get-VM','Get-Snapshot','Get-VMHost','Get-VMHostNetwork','Set-VMHostNetwork','Get-PowerCLIConfiguration')
    $core = @(Get-Module -ListAvailable VMware.VimAutomation.Core)
    [pscustomobject]@{
        PowerShell = $PSVersionTable.PSVersion.ToString()
        Edition = $PSVersionTable.PSEdition
        Platform = $PSVersionTable.Platform
        Architecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
        Modules = @(Get-Module -ListAvailable | Where-Object Name -Match '^(VMware|VCF|Pester|PSScriptAnalyzer)' |
            Select-Object Name, @{Name='Version';Expression={$_.Version.ToString()}})
        Commands = @(foreach ($name in $names) {
            [pscustomobject]@{
                Name = $name
                ImportedAvailable = [bool] (Get-Command $name -ListImported -ErrorAction SilentlyContinue)
                ExportedByAvailableModule = [bool] (@($core | Where-Object { $_.ExportedCommands.ContainsKey($name) }).Count)
            }
        })
        CoreModuleAvailable = $core.Count -gt 0
    }
}
function Initialize-ToolkitPowerCli {
    [CmdletBinding()]
    param()
    Import-Module VMware.VimAutomation.Core -Global -ErrorAction Stop -WarningAction Stop 3>$null
    foreach ($required in @('Connect-VIServer','Disconnect-VIServer','Get-VM','Get-Snapshot','Get-VMHost','Get-VMHostNetwork','Set-VMHostNetwork','Get-PowerCLIConfiguration')) {
        $command = Get-Command $required -Module VMware.VimAutomation.Core -ErrorAction Stop
        if ($command.CommandType -ne 'Cmdlet') { throw 'Expected a PowerCLI cmdlet.' }
    }
    $configuration = @(Get-PowerCLIConfiguration -Scope Session -ErrorAction Stop -WarningAction Stop 3>$null)
    if ($configuration.Count -ne 1 -or [string] $configuration[0].InvalidCertificateAction -ne 'Fail') {
        throw 'Explicit Session certificate policy Fail is required.'
    }
}
function Test-ToolkitTlsConnection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $HostName, [ValidateRange(1,60)][int] $TimeoutSeconds = 10)
    # Called only behind the runner's explicit Connect gate. No trust callback/exception.
    $client = [System.Net.Sockets.TcpClient]::new()
    $stream = $null
    $timeout = [System.Threading.CancellationTokenSource]::new([timespan]::FromSeconds($TimeoutSeconds))
    try {
        $client.ConnectAsync($HostName, 443, $timeout.Token).AsTask().GetAwaiter().GetResult()
        $stream = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
        $options = [System.Net.Security.SslClientAuthenticationOptions]::new()
        $options.TargetHost = $HostName
        $options.EnabledSslProtocols = [System.Security.Authentication.SslProtocols]::Tls12 -bor [System.Security.Authentication.SslProtocols]::Tls13
        $options.CertificateRevocationCheckMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
        $stream.AuthenticateAsClientAsync($options, $timeout.Token).GetAwaiter().GetResult()
        if (-not $stream.IsAuthenticated -or -not $stream.IsEncrypted) { throw 'TLS authentication failed.' }
        # Do not export certificate identities, subject, SAN or thumbprints.
        [pscustomobject]@{Status='Passed';Protocol=$stream.SslProtocol.ToString();CertificateValidation='PlatformChainAndHostname';Revocation='Online'}
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        $client.Dispose()
        $timeout.Dispose()
    }
}
function Initialize-ToolkitEvidenceDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Directory, [Parameter(Mandatory)][string] $RepositoryRoot)
    if ($Directory -match '^(?:\\\\|//|[a-z]+://)') { throw 'Use local evidence storage, not a network path.' }
    $full = [IO.Path]::GetFullPath($Directory)
    if ($IsWindows -and [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full)).DriveType -eq [IO.DriveType]::Network) {
        throw 'Network drives are not permitted for lab evidence.'
    }
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($full.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Evidence must be outside this Git repository.'
    }
    $cursor = [IO.DirectoryInfo]::new($full)
    while ($null -ne $cursor) {
        if ($cursor.Exists -and ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Evidence paths through symbolic links or reparse points are not permitted.'
        }
        $cursor = $cursor.Parent
    }
    $null = [IO.Directory]::CreateDirectory($full)
    if ($IsWindows) {
        # Fail closed if an owner-only ACL cannot be applied. Windows behavior needs lab validation.
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl = [Security.AccessControl.DirectorySecurity]::new()
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetOwner($sid)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $full -AclObject $acl -ErrorAction Stop
    } else {
        [IO.File]::SetUnixFileMode($full, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    }
    $full
}
function Save-ToolkitLabEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Evidence,[Parameter(Mandatory)][string] $Directory)
    # Create a new random name; never overwrite an earlier run, and never serialize raw providers.
    $name = 'lab-' + [guid]::NewGuid().ToString('N') + '.json'
    $path = Join-Path $Directory $name
    $options = [IO.FileStreamOptions]::new()
    $options.Mode = [IO.FileMode]::CreateNew
    $options.Access = [IO.FileAccess]::Write
    $options.Share = [IO.FileShare]::None
    if (-not $IsWindows) { $options.UnixCreateMode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite }
    $file = [IO.FileStream]::new($path, $options)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Evidence | ConvertTo-Json -Depth 8))
        $file.Write($bytes,0,$bytes.Length)
    } finally { $file.Dispose() }
    # File names are nonidentifying; do not return the private absolute path.
    $name
}
function Invoke-ToolkitReadProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Tool,[Parameter(Mandatory)][hashtable] $Arguments)
    try {
        $rows = @(& $Tool @Arguments -ErrorAction Stop -WarningAction Stop -InformationAction Ignore -Verbose:$false -Debug:$false 3>$null)
        [pscustomobject]@{Outcome='Completed';RecordCount=$rows.Count;ErrorCode=$null}
    } catch {
        # Do not serialize message, ErrorRecord, target, stack, inventory or provider IDs.
        [pscustomobject]@{Outcome='Failed';RecordCount=$null;ErrorCode='ReadProbeFailed'}
    }
}
Export-ModuleMember -Function Get-ToolkitLabEnvironment, Initialize-ToolkitPowerCli, Test-ToolkitTlsConnection, Initialize-ToolkitEvidenceDirectory, Save-ToolkitLabEvidence, Invoke-ToolkitReadProbe
