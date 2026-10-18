# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
BeforeAll {
    $root=Split-Path $PSScriptRoot -Parent
    $vcf=Join-Path $root 'scripts/VCF'
    function New-FixturePage { param($Entry) [pscustomobject]@{elements=@($Entry);pageMetadata=[pscustomobject]@{pageNumber=0;totalPages=1;totalElements=1}} }
}
Describe 'Offline VCF response adapters' {
    It 'Projects domain inventory and omits extra sensitive fields' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-domains.json" -Raw | ConvertFrom-Json
        $page.elements[0] | Add-Member NoteProperty password 'SYNTHETIC_DO_NOT_ECHO'
        $row=& "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only'
        $row.Domain | Should -Be 'lab-domain'
        $row.Mode | Should -Be 'Offline'
        $row.ContractVerifiedForProductVersion | Should -BeFalse
        ($row | ConvertTo-Json) | Should -Not -Match 'SYNTHETIC_DO_NOT_ECHO|password'
    }
    It 'Reports only SDDC Manager versions, not a complete VCF BOM' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-managers.json" -Raw | ConvertFrom-Json
        $row=& "$vcf/Get-VCFVersions.ps1" -Response $page -SourceVersion 'fixture-only'
        $row.Component | Should -Be 'SDDC_MANAGER'
        $row.Version | Should -Be 'fixture-version'
    }
    It 'Never equates successful historical SoS tasks with healthy infrastructure' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-health.json" -Raw | ConvertFrom-Json
        $row=& "$vcf/Get-VCFHealth.ps1" -Response $page -SourceVersion 'fixture-only'
        $row.TaskStatus | Should -Be 'COMPLETED_WITH_SUCCESS'
        $row.CurrentInfrastructureHealth | Should -Be 'Unknown'
    }
    It 'Projects certificate metadata without exporting PEM, subject or raw errors' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-certificates.json" -Raw | ConvertFrom-Json
        $page.elements[0] | Add-Member NoteProperty pemEncoded 'SYNTHETIC_PEM_CONTENT'
        $row=& "$vcf/Get-VCFCertificates.ps1" -Response $page -SourceVersion 'fixture-only'
        $row.TrustVerified | Should -BeFalse
        $row.ReportedExpirationStatus | Should -Be 'ACTIVE'
        ($row | ConvertTo-Json) | Should -Not -Match 'SYNTHETIC_PEM_CONTENT|pemEncoded'
    }
    It 'Marks certificate retrieval failures Unknown' {
        $entry=[pscustomobject]@{resourceName='lab';resourceType='VCENTER';getCertificateError='Synthetic retrieval failure'}
        $row=& "$vcf/Get-VCFCertificates.ps1" -Response (New-FixturePage $entry) -SourceVersion 'fixture-only'
        $row.RetrievalFailed | Should -BeTrue
        $row.ReportedExpirationStatus | Should -Be 'Unknown'
        $row.NotAfter | Should -BeNullOrEmpty
    }
    It 'Handles explicitly empty pages across all four adapters' {
        $page=[pscustomobject]@{elements=@();pageMetadata=[pscustomobject]@{pageNumber=0;totalPages=0;totalElements=0}}
        foreach ($file in (Get-ChildItem $vcf -Filter '*.ps1' | Where-Object { (Get-Command $_.FullName).Parameters.ContainsKey('Response') })) {
            @(& $file.FullName -Response $page -SourceVersion 'fixture-only').Count | Should -Be 0
        }
    }
    It 'Rejects API errors and missing metadata instead of treating them as empty inventory' {
        foreach ($page in @([pscustomobject]@{errorCode='UNAUTHORIZED'},[pscustomobject]@{elements=@()})) {
            { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' } | Should -Throw '*response rejected*'
        }
    }
    It 'Rejects incomplete or multipage input without guessing URLs' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-domains.json" -Raw | ConvertFrom-Json
        $page.pageMetadata.totalPages=2
        { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' } | Should -Throw
        $page.pageMetadata.totalPages=1; $page.pageMetadata.totalElements=2
        { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' } | Should -Throw
    }
    It 'Rejects malformed element types, timestamps and incomplete versions' {
        { & "$vcf/Get-VCFVersions.ps1" -Response (New-FixturePage 'bad') -SourceVersion 'fixture-only' } | Should -Throw
        { & "$vcf/Get-VCFVersions.ps1" -Response (New-FixturePage ([pscustomobject]@{id='id';fqdn='lab'})) -SourceVersion 'fixture-only' } | Should -Throw
        { & "$vcf/Get-VCFHealth.ps1" -Response (New-FixturePage ([pscustomobject]@{id='id';status='PENDING';creationTimestamp='invalid'})) -SourceVersion 'fixture-only' } | Should -Throw
    }
    It 'Emits zero records when a later response element is invalid' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-domains.json" -Raw | ConvertFrom-Json
        $page.elements+= [pscustomobject]@{id='incomplete'}
        $page.pageMetadata.totalElements=2
        $seen=[System.Collections.Generic.List[object]]::new()
        try { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' | ForEach-Object { $seen.Add($_) } } catch { }
        $seen.Count | Should -Be 0
    }
    It 'Contains no HTTP clients, credential/token parameters, file writes or live transport' {
        foreach ($file in Get-ChildItem $vcf -Filter '*.ps1') {
            $source=Get-Content $file.FullName -Raw
            $source | Should -Not -Match 'Invoke-RestMethod|Invoke-WebRequest|HttpClient|SkipCertificateCheck|Set-Content|Out-File'
            (Get-Command $file.FullName).Parameters.Keys | Should -Not -Contain 'Credential'
            (Get-Command $file.FullName).Parameters.Keys | Should -Not -Contain 'Token'
        }
    }
    It 'Supports string timestamps and JSON-typed UTC timestamps consistently' {
        $entry=[pscustomobject]@{id='fixture';status='PENDING';creationTimestamp='2026-10-17T12:00:00+02:00'}
        $row=& "$vcf/Get-VCFHealth.ps1" -Response (New-FixturePage $entry) -SourceVersion 'fixture-only'
        $row.Created.UtcDateTime.Hour | Should -Be 10
        $entry.creationTimestamp=[datetime]::new(2026,10,17,10,0,0,[DateTimeKind]::Utc)
        $row=& "$vcf/Get-VCFHealth.ps1" -Response (New-FixturePage $entry) -SourceVersion 'fixture-only'
        $row.Created.UtcDateTime.Hour | Should -Be 10
    }
    It 'Rejects ambiguous timezone-free timestamps' {
        $entry=[pscustomobject]@{id='fixture';status='PENDING';creationTimestamp='2026-10-17T10:00:00'}
        { & "$vcf/Get-VCFHealth.ps1" -Response (New-FixturePage $entry) -SourceVersion 'fixture-only' } | Should -Throw
        $entry.creationTimestamp=[datetime]::new(2026,10,17,10,0,0,[DateTimeKind]::Unspecified)
        { & "$vcf/Get-VCFHealth.ps1" -Response (New-FixturePage $entry) -SourceVersion 'fixture-only' } | Should -Throw
    }
    It 'Rejects inconsistent pagination metadata in every adapter' {
        foreach ($file in (Get-ChildItem $vcf -Filter '*.ps1' | Where-Object { (Get-Command $_.FullName).Parameters.ContainsKey('Response') })) {
            foreach ($bad in @($null,$true,-1,1.5,'1')) {
                $page=New-FixturePage ([pscustomobject]@{id='fixture'})
                $page.pageMetadata.totalPages=$bad
                { & $file.FullName -Response $page -SourceVersion 'fixture-only' } | Should -Throw
            }
        }
    }

    It 'Projects representative domains and manager versions while omitting nested identities' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-domains-representative.json" -Raw | ConvertFrom-Json
        $rows=@(& "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only')
        $rows.Count | Should -Be 2
        $rows.DomainStatus | Should -Contain 'ERROR'
        ($rows | ConvertTo-Json) | Should -Not -Match 'fixture-operator|vcenters'
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-managers-representative.json" -Raw | ConvertFrom-Json
        $rows=@(& "$vcf/Get-VCFVersions.ps1" -Response $page -SourceVersion 'fixture-only')
        $rows.Count | Should -Be 2
        ($rows | ConvertTo-Json) | Should -Not -Match 'basicAuthDetails|fixture-only.*username|192.0.2.10'
    }
    It 'Keeps current health Unknown for all documented task states' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-health-representative.json" -Raw | ConvertFrom-Json
        $rows=@(& "$vcf/Get-VCFHealth.ps1" -Response $page -SourceVersion 'fixture-only')
        $rows.Count | Should -Be 4
        @($rows | Where-Object CurrentInfrastructureHealth -NE 'Unknown').Count | Should -Be 0
    }
    It 'Distinguishes reported expired certificates from retrieval failure and does not return keys' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-certificates-representative.json" -Raw | ConvertFrom-Json
        $rows=@(& "$vcf/Get-VCFCertificates.ps1" -Response $page -SourceVersion 'fixture-only')
        $rows.Count | Should -Be 3
        $rows[1].ReportedExpirationStatus | Should -Be 'EXPIRED'
        $rows[2].ReportedExpirationStatus | Should -Be 'Unknown'
        ($rows | ConvertTo-Json) | Should -Not -Match 'fixture-public-key|fixture-certificate-omitted|Synthetic retrieval failure|subjectAlternativeName'
    }

    It 'Rejects mixed API-error and empty data envelopes in all four adapters' {
        foreach ($file in (Get-ChildItem $vcf -Filter '*.ps1' | Where-Object { (Get-Command $_.FullName).Parameters.ContainsKey('Response') })) {
            foreach ($marker in @('errorCode','errorType','message','nestedErrors','referenceToken','error','errors')) {
                $page=[pscustomobject]@{elements=@();pageMetadata=[pscustomobject]@{pageNumber=0;totalPages=0;totalElements=0}}
                $page | Add-Member NoteProperty $marker 'SYNTHETIC_API_FAILURE'
                { & $file.FullName -Response $page -SourceVersion 'fixture-only' } | Should -Throw '*response rejected*'
            }
        }
    }
    It 'Does not interpret null or empty error markers as a valid empty inventory' {
        foreach ($markerValue in @($null,'')) {
            $page=[pscustomobject]@{elements=@();pageMetadata=[pscustomobject]@{pageNumber=0;totalPages=0;totalElements=0};errorCode=$markerValue}
            { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' } | Should -Throw
        }
    }
    It 'Rejects API error objects mixed into apparently valid domain data atomically' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-domains-representative.json" -Raw | ConvertFrom-Json
        $page.elements[1] | Add-Member NoteProperty errorCode 'SYNTHETIC_FAILURE'
        $seen=[System.Collections.Generic.List[object]]::new()
        try { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' | ForEach-Object { $seen.Add($_) } } catch { }
        $seen.Count | Should -Be 0
        { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' } | Should -Throw
    }
    It 'Rejects error-bearing pagination metadata and nonfinite values' {
        $page=Get-Content "$PSScriptRoot/fixtures/vcf-domains.json" -Raw | ConvertFrom-Json
        $page.pageMetadata | Add-Member NoteProperty errorType 'SyntheticFailure'
        { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' } | Should -Throw
        foreach ($number in @([double]::NaN,[double]::PositiveInfinity,[double]::NegativeInfinity)) {
            $page=Get-Content "$PSScriptRoot/fixtures/vcf-domains.json" -Raw | ConvertFrom-Json
            $page.pageMetadata.totalElements=$number
            { & "$vcf/Get-VCFInventory.ps1" -Response $page -SourceVersion 'fixture-only' } | Should -Throw
        }
    }

    It 'Rejects documented synthetic error fixtures across every analyzer without leaking their text' {
        foreach ($fixture in @('vcf-error-only.json','vcf-error-mixed.json')) {
            $page=Get-Content (Join-Path "$PSScriptRoot/fixtures" $fixture) -Raw | ConvertFrom-Json
            foreach ($file in (Get-ChildItem $vcf -Filter '*.ps1' | Where-Object { (Get-Command $_.FullName).Parameters.ContainsKey('Response') })) {
                try { & $file.FullName -Response $page -SourceVersion 'fixture-only'; throw 'Unexpected acceptance' }
                catch {
                    $_.FullyQualifiedErrorId | Should -BeLike 'Toolkit.VCF*ResponseInvalid*'
                    $_.Exception.Message | Should -Not -Match 'SYNTHETIC_UNAUTHORIZED|Synthetic API failure'
                }
            }
        }
    }

}
