# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $vcf=Join-Path $root 'scripts/VCF'
    $fixtures=Join-Path $PSScriptRoot 'fixtures'
}
Describe 'Local VCF export contracts (synthetic only)' {
    It 'Reads single and complete multipage exports for every analyzer' {
        foreach ($pair in @(@('Inventory','domains'),@('Versions','managers'),@('Health','health'),@('Certificates','certificates'))) {
            $single=Join-Path $fixtures "vcf-$($pair[1])-representative.json"
            $pages=Join-Path $fixtures "vcf-$($pair[1])-pages.json"
            $before=(Get-FileHash $pages).Hash
            $a=@(& "$vcf/Get-VCF$($pair[0]).ps1" -Path $single -SourceVersion 'unverified-fixture')
            $b=@(& "$vcf/Get-VCF$($pair[0]).ps1" -Path $pages -SourceVersion 'unverified-fixture')
            $b.Count | Should -Be $a.Count
            ($b | ConvertTo-Json -Depth 10 -Compress) | Should -Be ($a | ConvertTo-Json -Depth 10 -Compress)
            (Get-FileHash $pages).Hash | Should -Be $before
        }
    }
    It 'Orders complete pages and rejects missing, repeated and inconsistent pages' {
        $pages=Get-Content "$fixtures/vcf-domains-pages.json" -Raw | ConvertFrom-Json
        @(& "$vcf/Get-VCFInventory.ps1" -Pages @($pages[1],$pages[0]) -SourceVersion 'fixture').Count | Should -Be 2
        { & "$vcf/Get-VCFInventory.ps1" -Pages @($pages[0]) -SourceVersion 'fixture' } | Should -Throw
        { & "$vcf/Get-VCFInventory.ps1" -Pages @($pages[0],$pages[0]) -SourceVersion 'fixture' } | Should -Throw
        $pages[1].pageMetadata.totalElements=3
        { & "$vcf/Get-VCFInventory.ps1" -Pages $pages -SourceVersion 'fixture' } | Should -Throw
    }
    It 'Rejects ambiguous or malformed JSON without exposing content or paths' {
        foreach ($json in @('{"elements":[],"ELEMENTS":[]}', '{"a":{"x":1,"x":2}}', '{"elements":[],}', '/*comment*/{}','null','[]','{"errorCode":"synthetic-private-marker"}')) {
            $file=Join-Path $TestDrive 'synthetic-private-marker.json'
            [IO.File]::WriteAllText($file,$json)
            $captured=[Collections.Generic.List[object]]::new()
            try { & "$vcf/Get-VCFInventory.ps1" -Path $file -SourceVersion fixture | ForEach-Object { $captured.Add($_) }; throw 'Unexpected success' }
            catch { $_.Exception.Message | Should -Not -Match 'synthetic-private-marker|Unexpected success' }
            $captured.Count | Should -Be 0
        }
    }
    It 'Rejects invalid UTF8, oversized files, missing paths and URLs' {
        $bad=Join-Path $TestDrive 'bad.json'
        [IO.File]::WriteAllBytes($bad,[byte[]]@(255,255))
        { & "$vcf/Get-VCFInventory.ps1" -Path $bad -SourceVersion fixture } | Should -Throw
        [IO.File]::WriteAllBytes($bad,[byte[]]::new(16777217))
        { & "$vcf/Get-VCFInventory.ps1" -Path $bad -SourceVersion fixture } | Should -Throw
        foreach ($path in @((Join-Path $TestDrive missing),'https://example.invalid/export.json','//example.invalid/export.json')) {
            { & "$vcf/Get-VCFInventory.ps1" -Path $path -SourceVersion fixture } | Should -Throw
        }
    }
    It 'Rejects API errors embedded in a later page without emitting partial records' {
        $pages=Get-Content "$fixtures/vcf-domains-pages.json" -Raw | ConvertFrom-Json
        $pages[1] | Add-Member errorCode 'fixture-denied'
        $captured=[Collections.Generic.List[object]]::new()
        try { & "$vcf/Get-VCFInventory.ps1" -Pages $pages -SourceVersion fixture | ForEach-Object { $captured.Add($_) } } catch { }
        $captured.Count | Should -Be 0
    }
    It 'Rejects symlinks and excessive nesting' {
        $target=Join-Path $TestDrive 'target.json'
        Copy-Item "$fixtures/vcf-domains.json" $target
        $link=Join-Path $TestDrive 'link.json'
        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        { & "$vcf/Get-VCFInventory.ps1" -Path $link -SourceVersion fixture } | Should -Throw
        [IO.File]::WriteAllText($target,('[' * 66)+(']' * 66))
        { & "$vcf/Get-VCFInventory.ps1" -Path $target -SourceVersion fixture } | Should -Throw
    }
}
Describe 'Additional file and page boundaries' {
    It 'Reads BOM UTF8 and explicit empty exports' {
        $file=Join-Path $TestDrive 'empty.json'
        $json='{"elements":[],"pageMetadata":{"pageNumber":0,"totalPages":0,"totalElements":0}}'
        [IO.File]::WriteAllText($file,$json,[Text.UTF8Encoding]::new($true))
        @(& "$vcf/Get-VCFInventory.ps1" -Path $file -SourceVersion fixture).Count | Should -Be 0
    }
    It 'Rejects contradictory counts and undersized pageSize' {
        foreach ($mutation in @('count','size','index')) {
            $pages=Get-Content "$fixtures/vcf-domains-pages.json" -Raw | ConvertFrom-Json
            switch ($mutation) {
                count { foreach ($page in $pages) { $page.pageMetadata.totalElements=3 } }
                size { $pages[1].pageMetadata.pageSize=0 }
                index { $pages[1].pageMetadata.pageNumber=2 }
            }
            { & "$vcf/Get-VCFInventory.ps1" -Pages $pages -SourceVersion fixture } | Should -Throw
        }
    }
}
