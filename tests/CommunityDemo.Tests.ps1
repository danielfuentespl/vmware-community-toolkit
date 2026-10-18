# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $example=Join-Path $root 'examples/Invoke-CommunityOfflineDemo.ps1'
}
Describe 'Reproducible fictional community demonstration' {
    It 'Combines the six documented demonstrations without PowerCLI and refuses overwrite' {
        $path=Join-Path $TestDrive 'community.html'
        $demo=& $example -OutputPath $path
        $demo.Mode | Should -Be FictionalOfflineDemo
        $demo.RealVmwareValidated | Should -BeFalse
        $demo.Inventory.Count | Should -Be 1
        $demo.Snapshots.Count | Should -Be 1
        $demo.Changes.Count | Should -Be 5
        $demo.VCF.PSObject.Properties.Name.Count | Should -Be 7
        $demo.VCF.OperationsAlerts.Count | Should -Be 2
        $html=Get-Content $path -Raw
        foreach ($key in @('VMs','Snapshots','HostSecurity','HostFirewall','HostSyslog','VCFLifecycle','VCFOperationsAlerts','VCFLicensing')) {
            $html | Should -Match "id=`"section-$key`""
        }
        $html | Should -Not -Match '<script|<iframe|<link|https?://|src='
        $before=(Get-FileHash $path).Hash
        { & $example -OutputPath $path } | Should -Throw
        (Get-FileHash $path).Hash | Should -Be $before
    }
}
