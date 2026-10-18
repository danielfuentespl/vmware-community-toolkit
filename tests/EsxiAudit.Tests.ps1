# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    function Get-VMHost { [CmdletBinding()]param($Server,$Name) throw 'Unexpected provider call' }
    function Get-View { [CmdletBinding()]param($Server,$Id,$Property) throw 'Unexpected provider call' }
    function Get-VMHostService { [CmdletBinding()]param($Server,$VMHost) throw 'Unexpected provider call' }
    function Get-VMHostFirewallException { [CmdletBinding()]param($Server,$VMHost,$Name) throw 'Unexpected provider call' }
    function Get-AdvancedSetting { [CmdletBinding()]param($Server,$Entity,$Name) throw 'Unexpected provider call' }
    function Get-VMHostNtpServer { [CmdletBinding()]param($Server,$VMHost) throw 'Unexpected provider call' }
    function Read-AuditFixture { Get-Content (Join-Path $PSScriptRoot 'fixtures/esxi-audit-projections.json') -Raw | ConvertFrom-Json }
}
Describe 'Read-only audit <Tool>' -ForEach @(
    @{Tool='Security/Get-VMHostSecurityConfiguration';Expected=1},
    @{Tool='Network/Get-VMHostFirewallReport';Expected=1},
    @{Tool='Security/Get-VMHostAdvancedSettings';Expected=1},
    @{Tool='Logging/Get-VMHostSyslogConfiguration';Expected=5},
    @{Tool='Network/Get-VMHostTimeConfiguration';Expected=1}
) {
    BeforeEach {
        $data=Read-AuditFixture
        $fakeConnection=[pscustomobject]@{Name='vc.example.invalid';IsConnected=$true}
        $path=Join-Path $root "scripts/$Tool.ps1"
        $arguments=@{Server=$fakeConnection}
        if ($Tool -eq 'Security/Get-VMHostAdvancedSettings') { $arguments.SettingName='Syslog.global.logHost' }
        Mock Get-VMHost { $data.hosts }
        Mock Get-View { $data.views }
        Mock Get-VMHostService { $data.services }
        Mock Get-VMHostFirewallException { $data.firewall }
        Mock Get-AdvancedSetting { $data.settings | Where-Object { $_.Name -in $Name } }
        Mock Get-VMHostNtpServer { $data.ntpServers }
    }
    It 'Returns scoped observations without a vulnerability verdict' {
        $rows=@(& $path @arguments)
        $rows.Count | Should -Be $Expected
        $rows[0].Assessment | Should -Be NotEvaluated
        $rows[0].VIServer | Should -Be $fakeConnection.Name
        Should -Invoke Get-VMHost -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection }
    }
    It 'Handles empty visible hosts and refuses a disconnected connection' {
        Mock Get-VMHost { @() }
        @(& $path @arguments).Count | Should -Be 0
        $fakeConnection.IsConnected=$false
        { & $path @arguments } | Should -Throw '*connected VIServer*'
    }
    It 'Sanitizes permission/session failures without success records' {
        Mock Get-VMHost { throw [UnauthorizedAccessException]::new('fixture-private-audit-denial') }
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & $path @arguments | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure.FullyQualifiedErrorId | Should -Match 'Toolkit\..*Failed'
        $failure.Exception.Message | Should -Not -Match fixture-private-audit-denial
        $captured.Count | Should -Be 0
    }
    It 'Fails atomically on duplicate host identity after a valid first host' {
        $data.hosts+=,$data.hosts[0]
        $captured=[Collections.Generic.List[object]]::new();$failure=$null
        try { & $path @arguments | ForEach-Object { $captured.Add($_) } } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        $captured.Count | Should -Be 0
    }
    It 'Stops and suppresses raw provider warnings' {
        Mock Get-VMHost { Write-Warning 'fixture-private-warning' }
        $failure=$null;$streams=@()
        try { $streams=@(& $path @arguments 3>&1) } catch { $failure=$_ }
        $failure | Should -Not -BeNullOrEmpty
        ($streams | Out-String) | Should -Not -Match fixture-private-warning
    }
}
Describe 'Audit evidence boundaries and HTML integration' {
    BeforeEach {
        $data=Read-AuditFixture
        $fakeConnection=[pscustomobject]@{Name='vc.example.invalid';IsConnected=$true}
        Mock Get-VMHost { $data.hosts }
        Mock Get-View { $data.views }
        Mock Get-VMHostService { $data.services }
        Mock Get-VMHostFirewallException { $data.firewall }
        Mock Get-AdvancedSetting { $data.settings | Where-Object { $_.Name -in $Name } }
        Mock Get-VMHostNtpServer { $data.ntpServers }
    }
    It 'Reports optional lockdown absence as Unknown without falling back to adminDisabled' {
        $data.views[0].Config.PSObject.Properties.Remove('LockdownMode')
        $data.views[0].Config | Add-Member AdminDisabled $true
        $rows=@(& "$root/scripts/Security/Get-VMHostSecurityConfiguration.ps1" -Server $fakeConnection)
        $rows[0].LockdownMode | Should -Be Unknown
        Should -Invoke Get-View -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection -and $Property -eq 'Config.LockdownMode' }
        Should -Invoke Get-VMHostService -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection -and $VMHost.Id -eq $data.hosts[0].Id }
    }
    It 'Uses Unknown for empty service/exception evidence and rejects malformed flags' {
        Mock Get-VMHostService { @() }; Mock Get-VMHostFirewallException { @() }
        (& "$root/scripts/Security/Get-VMHostSecurityConfiguration.ps1" -Server $fakeConnection).ServiceRunning | Should -Be Unknown
        (& "$root/scripts/Network/Get-VMHostFirewallReport.ps1" -Server $fakeConnection).Observation | Should -Be NoMatchingExceptions
        Mock Get-VMHostService { $data.services }
        $data.services[0].Running='false'
        { & "$root/scripts/Security/Get-VMHostSecurityConfiguration.ps1" -Server $fakeConnection } | Should -Throw
    }
    It 'Rejects repeated services, rules and settings instead of emitting duplicate observations' {
        $data.services+=,$data.services[0];$data.firewall+=,$data.firewall[0];$data.settings+=,$data.settings[0]
        { & "$root/scripts/Security/Get-VMHostSecurityConfiguration.ps1" -Server $fakeConnection } | Should -Throw
        { & "$root/scripts/Network/Get-VMHostFirewallReport.ps1" -Server $fakeConnection } | Should -Throw
        { & "$root/scripts/Security/Get-VMHostAdvancedSettings.ps1" -Server $fakeConnection -SettingName Syslog.global.logHost } | Should -Throw
    }
    It 'Scopes secondary firewall/advanced queries and retains unknown missing settings' {
        $data.settings=@()
        $rows=@(& "$root/scripts/Logging/Get-VMHostSyslogConfiguration.ps1" -Server $fakeConnection)
        $rows.Count | Should -Be 5
        @($rows | Where-Object ValueState -eq Unknown).Count | Should -Be 5
        Should -Invoke Get-AdvancedSetting -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection -and $Entity.Id -eq $data.hosts[0].Id -and $Name.Count -eq 5 }
        & "$root/scripts/Network/Get-VMHostFirewallReport.ps1" -Server $fakeConnection -RuleName 'fixture-*' | Out-Null
        Should -Invoke Get-VMHostFirewallException -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection -and $Name -eq 'fixture-*' }
    }
    It 'Withholds arbitrary setting values without evaluating their getters' {
        $s=[pscustomobject]@{Name='fixture.custom.setting';Type='String'}
        $s | Add-Member -MemberType ScriptProperty -Name Value -Value { throw 'fixture-sensitive-getter' }
        Mock Get-AdvancedSetting { $s }
        $row=& "$root/scripts/Security/Get-VMHostAdvancedSettings.ps1" -Server $fakeConnection -SettingName fixture.custom.setting
        $row.ValueState | Should -Be Withheld
        $row.Value | Should -Be '[Withheld]'
    }
    It 'Distinguishes blank configured logHost, unsupported keys and suspicious URI credentials' {
        $data.settings[0].Value=''
        $row=@(& "$root/scripts/Logging/Get-VMHostSyslogConfiguration.ps1" -Server $fakeConnection)[0]
        $row.ValueState | Should -Be Reported
        $row.Value | Should -BeExactly ''
        $data.settings[0].Value='ssl://fixture-user:fixture-not-real@syslog.example.invalid:1514'
        $row=@(& "$root/scripts/Logging/Get-VMHostSyslogConfiguration.ps1" -Server $fakeConnection)[0]
        $row.ValueState | Should -Be Withheld
        $row.Value | Should -Not -Match fixture-user
        { & "$root/scripts/Security/Get-VMHostAdvancedSettings.ps1" -Server $fakeConnection -SettingName '*' } | Should -Throw
    }
    It 'Rejects nonfinite, fractional and negative retention values' {
        foreach ($value in @([double]::NaN,[double]::PositiveInfinity,-1,1.5,'not-a-number')) {
            $data.settings[3].Value=$value
            { & "$root/scripts/Logging/Get-VMHostSyslogConfiguration.ps1" -Server $fakeConnection } | Should -Throw
        }
    }
    It 'Extends NTP observations with optional version-sensitive fields, never an independent sync verdict' {
        $row=& "$root/scripts/Network/Get-VMHostTimeConfiguration.ps1" -Server $fakeConnection
        $row.NtpServers[0] | Should -Be ntp.example.invalid
        $row.ReportedServiceSync | Should -BeFalse
        $row.IndependentSyncVerified | Should -BeFalse
        Should -Invoke Get-VMHostNtpServer -Times 1 -Exactly -ParameterFilter { $Server -eq $fakeConnection }
        $data.views[0].Config.DateTimeInfo=[pscustomobject]@{TimeZone=[pscustomobject]@{Key='UTC';GmtOffset=0}}
        $row=& "$root/scripts/Network/Get-VMHostTimeConfiguration.ps1" -Server $fakeConnection
        $row.ReportedProtocol | Should -Be Unknown
        $row.ReportedServiceSync | Should -Be Unknown
        $row.LastSyncUtc | Should -BeNullOrEmpty
    }
    It 'Rejects malformed offsets, ambiguous times and failed secondary queries atomically' {
        $data.views[0].Config.DateTimeInfo.TimeZone.GmtOffset=[double]::NaN
        { & "$root/scripts/Network/Get-VMHostTimeConfiguration.ps1" -Server $fakeConnection } | Should -Throw
        $data.views[0].Config.DateTimeInfo.TimeZone.GmtOffset=0
        $data.views[0].Config.DateTimeInfo.LastSyncTime=[datetime]::SpecifyKind([datetime]'2026-10-17',[DateTimeKind]::Unspecified)
        { & "$root/scripts/Network/Get-VMHostTimeConfiguration.ps1" -Server $fakeConnection } | Should -Throw
        Mock Get-View { throw [IO.IOException]::new('fixture-session-loss') }
        $failure=$null;$captured=@()
        try { $captured=@(& "$root/scripts/Network/Get-VMHostTimeConfiguration.ps1" -Server $fakeConnection) } catch { $failure=$_ }
        $failure.Exception.Message | Should -Not -Match fixture-session-loss
        $captured.Count | Should -Be 0
    }
    It 'Adds all five HTML sections only when supplied and escapes untrusted labels' {
        $envelope=[pscustomobject]@{
            ScopeId='fixture';CapturedAt=[datetimeoffset]'2026-10-17T00:00:00Z'
            HostSecurity=@(& "$root/scripts/Security/Get-VMHostSecurityConfiguration.ps1" -Server $fakeConnection)
            HostFirewall=@(& "$root/scripts/Network/Get-VMHostFirewallReport.ps1" -Server $fakeConnection)
            HostSyslog=@(& "$root/scripts/Logging/Get-VMHostSyslogConfiguration.ps1" -Server $fakeConnection)
            HostTime=@(& "$root/scripts/Network/Get-VMHostTimeConfiguration.ps1" -Server $fakeConnection)
            HostAdvancedSettings=@(& "$root/scripts/Security/Get-VMHostAdvancedSettings.ps1" -Server $fakeConnection -SettingName Syslog.global.logHost)
        }
        $envelope.HostFirewall[0].RuleName='<script>fixture-script</script>'
        $html=Join-Path $TestDrive 'audit.html'
        & "$root/scripts/Reporting/New-vSphereHealthReport.ps1" -Data $envelope -OutputPath $html | Out-Null
        $content=Get-Content $html -Raw
        ([regex]::Matches($content,'<section(?:\s[^>]*)?>')).Count | Should -Be 12
        $content | Should -Match '&lt;script&gt;'
        $content | Should -Not -Match '<script>'
        $content | Should -Match '<td>True</td>'
        $content | Should -Match '<td>NotEvaluated</td>'
    }
    It 'Keeps audit provider calls explicit and exposes no mutation or TLS bypass path' {
        foreach ($script in @('Security/Get-VMHostSecurityConfiguration','Network/Get-VMHostFirewallReport','Security/Get-VMHostAdvancedSettings','Logging/Get-VMHostSyslogConfiguration','Network/Get-VMHostTimeConfiguration')) {
            $tokens=$null;$parseErrors=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile("$root/scripts/$script.ps1",[ref]$tokens,[ref]$parseErrors)
            $parseErrors.Count | Should -Be 0
            $metadata=Get-Command "$root/scripts/$script.ps1"
            @($metadata.Parameters.Server.Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -Be 1
            foreach ($command in @($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true))) {
                $name=$command.GetCommandName()
                $name | Should -Not -Match '^(Connect-|Disconnect-|Set-VM|Set-Advanced|New-VM|Remove-|Invoke-RestMethod|Invoke-WebRequest)'
                if ($name -in @('Get-VMHost','Get-View','Get-VMHostService','Get-VMHostFirewallException','Get-AdvancedSetting')) {
                    @($command.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Server' }).Count | Should -Be 1
                }
            }
        }
    }
    It 'Reapplies value withholding in HTML even when forged input asserts Reported' {
        $envelope=[pscustomobject]@{ScopeId='fixture';CapturedAt='2026-10-17T00:00:00Z';HostAdvancedSettings=@([pscustomobject]@{VMHostId='fixture';SettingName='fixture.custom';ValueState='Reported';Value='fixture-sensitive-marker';Assessment='Vulnerable'})}
        $html=Join-Path $TestDrive 'withheld.html'
        & "$root/scripts/Reporting/New-vSphereHealthReport.ps1" -Data $envelope -OutputPath $html | Out-Null
        $content=Get-Content $html -Raw
        $content | Should -Not -Match 'fixture-sensitive-marker|Vulnerable'
        $content | Should -Match '\[Withheld\]'
    }
}
