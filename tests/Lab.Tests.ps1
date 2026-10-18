# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root = Split-Path $PSScriptRoot -Parent
    $runner = Join-Path $root 'scripts/Lab/Invoke-ToolkitLabValidation.ps1'
    $support = Join-Path $root 'scripts/Private/Lab.Support.psm1'
    Import-Module $support -Force
    function Get-PowerCLIConfiguration { [CmdletBinding()] param($Scope) throw 'No live module' }
    function Connect-VIServer { [CmdletBinding()] param($Server,$Credential,[switch]$NotDefault) throw 'No real connections' }
    function Disconnect-VIServer { [CmdletBinding(SupportsShouldProcess)] param($Server) throw 'No real connections' }
}
Describe 'Laboratory runner orchestration with no network' {
    BeforeEach {
        $directory = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $secure = ConvertTo-SecureString 'synthetic-fixture-only' -AsPlainText -Force
        $credential = [pscredential]::new('fixture-user', $secure)
        $fakeConnection = [pscustomobject]@{Name='sensitive-target.example.invalid';IsConnected=$true}
        Mock Get-ToolkitLabEnvironment {
            [pscustomobject]@{PowerShell='fixture';CoreModuleAvailable=$true;Modules=@();Commands=@([pscustomobject]@{Name='Get-VM'})}
        }
        Mock Initialize-ToolkitPowerCli {}
        Mock Test-ToolkitTlsConnection { [pscustomobject]@{Status='Passed';Protocol='Tls13'} }
        Mock Connect-VIServer { $fakeConnection }
        Mock Disconnect-VIServer {}
        Mock Invoke-ToolkitReadProbe { [pscustomobject]@{Outcome='Completed';RecordCount=1;ErrorCode=$null} }
    }
    It 'Defaults to local preflight and never probes DNS/TLS or authenticates' {
        $summary = & $runner -EvidenceDirectory $directory
        $summary.Outcome | Should -Be 'PreflightOnly'
        $evidence=Get-Content (Join-Path $directory $summary.EvidenceFile) -Raw | ConvertFrom-Json
        $evidence.NetworkAttempted | Should -BeFalse
        $evidence.Tests.Count | Should -Be 0
        Should -Invoke Test-ToolkitTlsConnection -Times 0
        Should -Invoke Connect-VIServer -Times 0
    }
    It 'Does not connect when Connect is explicitly false' {
        & $runner -EvidenceDirectory $directory -Connect:$false -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential | Out-Null
        Should -Invoke Connect-VIServer -Times 0
    }
    It 'Requires explicit Connect, target and credential via parameter sets' {
        $command=Get-Command $runner
        @($command.ParameterSets | Where-Object Name -EQ 'Connect').Parameters | Where-Object Name -In @('VIServer','EndpointType','Credential','Connect') | ForEach-Object { $_.IsMandatory | Should -BeTrue }
        $command.Parameters.Keys | Should -Not -Contain 'Password'
        $command.Parameters.Keys | Should -Not -Contain 'AllowWrite'
    }
    It 'Blocks missing PowerCLI before TLS or login' {
        Mock Get-ToolkitLabEnvironment { [pscustomobject]@{CoreModuleAvailable=$false;Modules=@();Commands=@()} }
        { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential } | Should -Throw '*did not complete*'
        Should -Invoke Test-ToolkitTlsConnection -Times 0
        Should -Invoke Connect-VIServer -Times 0
    }
    It 'Rejects insecure Session certificate policy before any network' {
        Mock Initialize-ToolkitPowerCli { throw 'Explicit Session certificate policy Fail is required.' }
        { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential } | Should -Throw
        Should -Invoke Test-ToolkitTlsConnection -Times 0
        Should -Invoke Connect-VIServer -Times 0
    }
    It 'Blocks login after TLS failure without recording the private message' {
        Mock Test-ToolkitTlsConnection { throw 'PRIVATE_TLS_HOST_MARKER' }
        { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential } | Should -Throw
        Should -Invoke Connect-VIServer -Times 0
        (Get-Content (Get-ChildItem $directory -Filter '*.json').FullName -Raw) | Should -Not -Match 'PRIVATE_TLS_HOST_MARKER|vc.example.invalid|fixture-user|synthetic-fixture-only'
    }
    It 'Runs exactly three read probes and disconnects its explicit session' {
        $summary=& $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential -VMName 'private-vm-*' -HostName 'private-host-*'
        $summary.Outcome | Should -Be 'ReadProbesCompleted'
        Should -Invoke Invoke-ToolkitReadProbe -Times 3
        Should -Invoke Connect-VIServer -Times 1 -ParameterFilter {$Server -eq 'vc.example.invalid' -and $NotDefault}
        Should -Invoke Disconnect-VIServer -Times 1 -ParameterFilter {$Server -eq $fakeConnection}
        $json=Get-Content (Join-Path $directory $summary.EvidenceFile) -Raw
        $json | Should -Not -Match 'private-vm|private-host|sensitive-target|fixture-user|synthetic-fixture-only'
        ($json | ConvertFrom-Json).Tests.Count | Should -Be 3
    }
    It 'Marks failed probes and still disconnects without a success outcome' {
        Mock Invoke-ToolkitReadProbe { [pscustomobject]@{Outcome='Failed';RecordCount=$null;ErrorCode='ReadProbeFailed'} }
        { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential } | Should -Throw
        Should -Invoke Disconnect-VIServer -Times 1
        $json=Get-Content (Get-ChildItem $directory -Filter '*.json').FullName -Raw | ConvertFrom-Json
        $json.Outcome | Should -Be 'Failed'
    }
    It 'Rejects ambiguous returned connections and closes each one' {
        Mock Connect-VIServer { @($fakeConnection,$fakeConnection) }
        { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential } | Should -Throw
        Should -Invoke Disconnect-VIServer -Times 2
        Should -Invoke Invoke-ToolkitReadProbe -Times 0
    }
    It 'Does not leave a partial returned connection open on a later login error' {
        Mock Connect-VIServer { $fakeConnection; Write-Error 'PRIVATE_CONNECTION_FAILURE' }
        { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential } | Should -Throw
        Should -Invoke Disconnect-VIServer -Times 1
    }
    It 'Treats disconnect failure as failure and redacts its message' {
        Mock Disconnect-VIServer { throw 'PRIVATE_DISCONNECT_MARKER' }
        { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter 'vc.example.invalid' -Credential $credential } | Should -Throw
        $json=Get-Content (Get-ChildItem $directory -Filter '*.json').FullName -Raw
        $json | Should -Not -Match 'PRIVATE_DISCONNECT_MARKER'
        ($json | ConvertFrom-Json).Disconnect | Should -Be 'Failed'
    }
    It 'Rejects URL/credential/port target strings during parameter binding' {
        foreach ($target in @('https://vc.example.invalid','user@vc.example.invalid','vc.example.invalid:443','vc*.example.invalid')) {
            { & $runner -EvidenceDirectory $directory -Connect -EndpointType vCenter -VCenter $target -Credential $credential } | Should -Throw
        }
        Should -Invoke Connect-VIServer -Times 0
    }
    It 'Rejects evidence inside Git before writing or connecting' {
        { & $runner -EvidenceDirectory (Join-Path $root 'never-created-evidence') } | Should -Throw '*outside Git*'
        Test-Path (Join-Path $root 'never-created-evidence') | Should -BeFalse
        Should -Invoke Connect-VIServer -Times 0
    }

    It 'Supports explicitly declared direct ESXi with the same read-only probes' {
        $summary=& $runner -EvidenceDirectory $directory -Connect -EndpointType ESXi -VIServer 'esxi.example.invalid' -Credential $credential -VMName 'lab-*' -HostName 'esxi.example.invalid'
        $summary.Outcome | Should -Be 'ReadProbesCompleted'
        $evidence=Get-Content (Join-Path $directory $summary.EvidenceFile) -Raw | ConvertFrom-Json
        $evidence.EndpointTypeDeclared | Should -Be 'ESXi'
        $evidence.SchemaVersion | Should -Be 2
        Should -Invoke Invoke-ToolkitReadProbe -Times 3
        Should -Invoke Connect-VIServer -Times 1 -ParameterFilter { $Server -eq 'esxi.example.invalid' -and $NotDefault }
        ($evidence | ConvertTo-Json -Depth 8) | Should -Not -Match 'esxi.example.invalid'
    }
    It 'Requires an explicit endpoint type and retains the VCenter parameter alias' {
        $command=Get-Command $runner
        $command.Parameters.EndpointType.Attributes.ValidValues | Should -Contain 'ESXi'
        $command.Parameters.EndpointType.Attributes.ValidValues | Should -Contain 'vCenter'
        $command.Parameters.VIServer.Aliases | Should -Contain 'VCenter'
        ($command.ParameterSets | Where-Object Name -EQ 'Connect').Parameters | Where-Object Name -EQ 'EndpointType' | ForEach-Object { $_.IsMandatory | Should -BeTrue }
    }
    It 'Redacts evidence-write errors instead of leaking private filesystem paths' {
        Mock Save-ToolkitLabEvidence { throw 'PRIVATE_FILESYSTEM_PATH' }
        { & $runner -EvidenceDirectory $directory } | Should -Throw 'Unable to write lab evidence; no successful run can be claimed.'
    }
    It 'Has no DNS setter or credential prompt path' {
        $source=Get-Content $runner -Raw
        $source | Should -Not -Match 'Set-VMHostDnsServers|Get-Credential|Export-Clixml|Start-Transcript'
    }
}
Describe 'Evidence and read-probe helpers' {
    It 'Only counts raw rows and suppresses fields' {
        $tool=Join-Path $TestDrive 'fixture-probe.ps1'
        Set-Content $tool '[CmdletBinding()]param(); [pscustomobject]@{Name="PRIVATE_MACHINE_MARKER";IP="192.0.2.1"}'
        $result=Invoke-ToolkitReadProbe -Tool $tool -Arguments @{}
        $result.RecordCount | Should -Be 1
        ($result | ConvertTo-Json) | Should -Not -Match 'PRIVATE_MACHINE_MARKER|192.0.2.1'
    }
    It 'Fails on warning-only omissions and emits no provider warning text' {
        $tool=Join-Path $TestDrive 'fixture-warning.ps1'
        Set-Content $tool '[CmdletBinding()]param(); Write-Warning "PRIVATE_WARNING_MARKER"'
        $result=Invoke-ToolkitReadProbe -Tool $tool -Arguments @{}
        $result.Outcome | Should -Be 'Failed'
        $result.RecordCount | Should -BeNullOrEmpty
        ($result | ConvertTo-Json) | Should -Not -Match 'PRIVATE_WARNING_MARKER'
    }
    It 'Writes separate restricted files without overwriting earlier evidence' {
        $directory=Initialize-ToolkitEvidenceDirectory -Directory (Join-Path $TestDrive 'evidence') -RepositoryRoot $root
        $a=Save-ToolkitLabEvidence -Directory $directory -Evidence @{Outcome='Prepared'}
        $b=Save-ToolkitLabEvidence -Directory $directory -Evidence @{Outcome='Prepared'}
        $a | Should -Not -Be $b
        @(Get-ChildItem $directory).Count | Should -Be 2
        if (-not $IsWindows) {
            [int][IO.File]::GetUnixFileMode((Join-Path $directory $a)) | Should -Be 384
            [int][IO.File]::GetUnixFileMode($directory) | Should -Be 448
        }
    }
    It 'Rejects UNC/URI storage before directory creation' {
        { Initialize-ToolkitEvidenceDirectory -Directory '//fixture-share/never-create' -RepositoryRoot $root } | Should -Throw '*local evidence*'
        { Initialize-ToolkitEvidenceDirectory -Directory 'https://example.invalid/never-create' -RepositoryRoot $root } | Should -Throw '*local evidence*'
    }
    It 'Refuses symlink evidence paths on the tested Unix platform' {
        if (-not $IsWindows) {
            $link=Join-Path $TestDrive 'link'
            $null=New-Item -ItemType SymbolicLink -Path $link -Target $root
            { Initialize-ToolkitEvidenceDirectory -Directory (Join-Path $link 'evidence') -RepositoryRoot $root } | Should -Throw '*symbolic links*'
        }
    }
    It 'Uses TLS chain/hostname checks, revocation and cancellation without a bypass' {
        $source=Get-Content $support -Raw
        $source | Should -Match 'TargetHost = \$HostName'
        $source | Should -Match 'X509RevocationMode]::Online'
        $source | Should -Match 'CancellationTokenSource'
        $source | Should -Not -Match 'RemoteCertificateValidationCallback|SkipCertificateCheck|SslPolicyErrors.*None'
        @([Net.Sockets.TcpClient].GetMethods() | Where-Object {$_.Name -eq 'ConnectAsync' -and $_.GetParameters().Count -eq 3 -and $_.GetParameters()[2].ParameterType -eq [Threading.CancellationToken]}).Count | Should -BeGreaterThan 0
    }
    It 'Contains no software installation or credential persistence in runtime scripts' {
        foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -Recurse -Include '*.ps1','*.psm1') {
            $text=Get-Content $file.FullName -Raw
            $text | Should -Not -Match 'Install-Module|Install-PSResource|Save-Module|Export-Clixml|New-VICredentialStoreItem|Start-Transcript'
        }
    }

}
