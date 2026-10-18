# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
<#
.SYNOPSIS
Experimental OFFLINE SDDC Manager certificates response projection.
.DESCRIPTION
Processes a parsed simulated/API-export response only. Makes no network calls.
Reference contract: GET /v1/domains/{id}/resource-certificates; product-version binding is NOT verified.
Output is a buffered projection, never evidence of current infrastructure health or trust.
.PARAMETER Response
One parsed PageOf response with an elements array and complete single-page metadata.
.PARAMETER Path
Literal local UTF-8 JSON file: one PageOf object or a complete array of pages.
No network paths, symlinks, duplicate JSON keys, comments or trailing commas; max 16 MiB/depth 64.
.PARAMETER Pages
Complete offline PageOf array; numbering, totals and uniqueness are validated.
.PARAMETER SourceVersion
Operator-provided product version label, not proof of compatibility.
.EXAMPLE
./Get-VCFCertificates.ps1 -Response $simulatedResponse -SourceVersion 'fixture-only'
.EXAMPLE
./Get-VCFCertificates.ps1 -Path './export.json' -SourceVersion 'operator-reported'
.NOTES
No credentials or tokens are accepted, persisted or returned. No PowerCLI dependency.
Fields are allowlisted; protect real response exports outside Git. See docs/VCF-API-MATRIX.md.
#>
[CmdletBinding(DefaultParameterSetName='Response')]
param(
    [Parameter(Mandatory,ParameterSetName='Response')][ValidateNotNull()][object] $Response,
    [Parameter(Mandatory,ParameterSetName='Path')][Alias('LiteralPath')][ValidateNotNullOrEmpty()][string] $Path,
    [Parameter(Mandatory,ParameterSetName='Pages')][ValidateNotNullOrEmpty()][object[]] $Pages,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()]
    [ValidateScript({ -not [string]::IsNullOrWhiteSpace($_) })]
    [string] $SourceVersion
)
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../Private/VCF.Response.psm1') -Scope Local -ErrorAction Stop
try {
    $entries = @(
        switch ($PSCmdlet.ParameterSetName) {
            'Path' { Read-VCFExport -Path $Path }
            'Pages' { Read-VCFCollection -Pages $Pages }
            default { Read-VCFPage -Response $Response }
        }
    )
    $rows = @(
        foreach ($entry in $entries) {
            Assert-VCFField -Element $entry -Field resourceName, resourceType
            $hasError = $null -ne $entry.PSObject.Properties['getCertificateError'] -and -not [string]::IsNullOrWhiteSpace([string] $entry.getCertificateError)
            $expiry = $null
            $state = 'Unknown'
            if (-not $hasError) {
                Assert-VCFField -Element $entry -Field expirationStatus
                $expiry = ConvertTo-VCFTimestamp -Value $entry.notAfter
                $state = $entry.expirationStatus
            }
            [pscustomobject]@{
                Source = 'SDDC Manager'
                Mode = 'Offline'
                SourceVersion = $SourceVersion
                ContractVerifiedForProductVersion = $false
                Resource = $entry.resourceName
                ResourceType = $entry.resourceType
                NotAfter = $expiry
                ReportedExpirationStatus = $state
                RetrievalFailed = $hasError
                TrustVerified = $false
            }
        }
    )
} catch {
    $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
        [System.InvalidOperationException]::new('Offline VCF certificates response rejected; no records were emitted.'),
        'Toolkit.VCFCertificatesResponseInvalid', [System.Management.Automation.ErrorCategory]::InvalidData, $null))
}
$rows
