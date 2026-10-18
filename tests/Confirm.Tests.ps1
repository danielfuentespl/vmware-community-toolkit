# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $setter=Join-Path $root 'scripts/Network/Set-VMHostDnsServers.ps1'
    function Get-VMHost { [CmdletBinding()] param($Server,$Name) throw 'No live provider' }
    function Get-VMHostNetwork { [CmdletBinding()] param($Server,$VMHost) throw 'No live provider' }
    function Set-VMHostNetwork { [CmdletBinding(SupportsShouldProcess)] param($Network,$DnsAddress,$DnsFromDhcp) throw 'Writes prohibited' }
}
Describe 'Phase 3 DNS write lock' {
    BeforeEach {
        $arguments=@{Server=[pscustomobject]@{Name='vc.example.invalid';IsConnected=$true};VMHostName='esxi.example.invalid';DnsAddress=@('192.0.2.53')}
        Mock Get-VMHost { [pscustomobject]@{Name='esxi.example.invalid'} }
        Mock Get-VMHostNetwork { [pscustomobject]@{DnsAddress=@('192.0.2.54');DnsFromDhcp=$true} }
        Mock Set-VMHostNetwork { throw 'Writes prohibited' }
    }
    It 'Rejects default invocation before discovery or confirmation' {
        { & $setter @arguments } | Should -Throw '*disabled during Phase 3*'
        Should -Invoke Get-VMHost -Times 0
        Should -Invoke Set-VMHostNetwork -Times 0
    }
    It 'Cannot be bypassed with Confirm false or true' {
        { & $setter @arguments -Confirm:$false } | Should -Throw '*disabled during Phase 3*'
        { & $setter @arguments -Confirm:$true } | Should -Throw '*disabled during Phase 3*'
        Should -Invoke Get-VMHost -Times 0
        Should -Invoke Set-VMHostNetwork -Times 0
    }
    It 'Cannot be bypassed by explicitly setting WhatIf false' {
        { & $setter @arguments -WhatIf:$false -Confirm:$false } | Should -Throw '*disabled during Phase 3*'
        Should -Invoke Set-VMHostNetwork -Times 0
    }
    It 'WhatIf permits only discovery and emits no success receipt' {
        @(& $setter @arguments -WhatIf).Count | Should -Be 0
        Should -Invoke Get-VMHostNetwork -Times 1
        Should -Invoke Set-VMHostNetwork -Times 0
    }
    It 'Still rejects equivalent IPv6 duplicates and IPv4 shorthand during preview' {
        $arguments.DnsAddress=@('2001:db8::53','2001:0db8:0:0:0:0:0:53')
        { & $setter @arguments -WhatIf } | Should -Throw '*Duplicate*'
        $arguments.DnsAddress=@('127.1')
        { & $setter @arguments -WhatIf } | Should -Throw
        Should -Invoke Get-VMHost -Times 0
    }
    It 'Still rejects wildcard targets in preview' {
        $arguments.VMHostName='esxi*'
        { & $setter @arguments -WhatIf } | Should -Throw
        Should -Invoke Set-VMHostNetwork -Times 0
    }
}
