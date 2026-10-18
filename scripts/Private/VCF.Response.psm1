# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
Set-StrictMode -Version Latest
function Assert-VCFSuccessObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Value)
    # Explicit vendor Error-model markers and common error envelopes are not PageOf data.
    # Certificate getCertificateError is a documented per-resource retrieval result, not this envelope.
    foreach ($field in @('errorCode','errorType','nestedErrors','causes','remediationMessage','referenceToken','error','errors','message')) {
        if ($null -ne $Value.PSObject.Properties[$field]) {
            throw 'API error or ambiguous mixed error/data response rejected.'
        }
    }
}
function Read-VCFPage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Response, [switch] $CollectionPage)
    if ($Response -is [string] -or $Response -is [array] -or
        $null -eq $Response.PSObject.Properties['elements'] -or
        $Response.elements -isnot [array] -or
        $null -eq $Response.PSObject.Properties['pageMetadata']) {
        throw 'Expected a parsed single PageOf response with elements array and pagination metadata.'
    }
    Assert-VCFSuccessObject -Value $Response
    $meta = $Response.pageMetadata
    if ($null -ne $meta) { Assert-VCFSuccessObject -Value $meta }
    foreach ($field in @('totalPages', 'totalElements', 'pageNumber')) {
        if ($null -eq $meta -or $null -eq $meta.PSObject.Properties[$field] -or
            $meta.$field -isnot [ValueType] -or $meta.$field -is [bool] -or
            $meta.$field -lt 0 -or [double] $meta.$field % 1 -ne 0) {
            throw 'Invalid pagination metadata.'
        }
    }
    if ($CollectionPage) {
        if ($meta.totalPages -lt 1 -or $meta.pageNumber -ge $meta.totalPages -or $Response.elements.Count -gt $meta.totalElements) {
            throw 'Invalid collection page metadata.'
        }
    } elseif (($Response.elements.Count -gt 0 -and $meta.totalPages -ne 1) -or $meta.totalPages -gt 1 -or $meta.pageNumber -ne 0 -or $meta.totalElements -ne $Response.elements.Count) {
        throw 'Incomplete or multi-page response. Offline tools do not invent pagination parameters.'
    }
    if ($null -ne $meta.PSObject.Properties['pageSize']) {
        if ($meta.pageSize -isnot [ValueType] -or $meta.pageSize -is [bool] -or
            -not [double]::IsFinite([double] $meta.pageSize) -or
            $meta.pageSize % 1 -ne 0 -or $meta.pageSize -lt $Response.elements.Count) {
            throw 'Invalid page size metadata.'
        }
    }
    foreach ($element in $Response.elements) {
        if ($null -eq $element -or $element -isnot [pscustomobject]) { throw 'Invalid response element.' }
        Assert-VCFSuccessObject -Value $element
    }
    $Response.elements
}
function Assert-VCFField {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object] $Element, [Parameter(Mandatory)][string[]] $Field)
    foreach ($name in $Field) {
        if ($null -eq $Element.PSObject.Properties[$name] -or $Element.$name -isnot [string] -or
            [string]::IsNullOrWhiteSpace($Element.$name)) {
            throw 'Required response field is missing or has an unsupported type.'
        }
    }
}
function ConvertTo-VCFTimestamp {
    [CmdletBinding()]
    [OutputType([datetimeoffset])]
    param([Parameter(Mandatory)][object] $Value)
    if ($Value -is [datetimeoffset]) { return $Value.ToUniversalTime() }
    if ($Value -is [datetime] -and $Value.Kind -ne [DateTimeKind]::Unspecified) {
        return [datetimeoffset]::new($Value).ToUniversalTime()
    }
    $parsed = [datetimeoffset]::MinValue
    if ($Value -isnot [string] -or
        $Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$' -or
        -not [datetimeoffset]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref] $parsed)) {
        throw 'Expected an ISO 8601 timestamp with an explicit timezone.'
    }
    $parsed.ToUniversalTime()
}
function Read-VCFCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][object[]] $Pages)
    if ($Pages.Count -gt 10000) { throw 'Too many export pages.' }
    if ($Pages.Count -eq 1) { return Read-VCFPage -Response $Pages[0] }
    $rows = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[long]]::new()
    $expectedPages = $null
    $expectedElements = $null
    foreach ($page in $Pages) {
        # Validate all pages and keep data buffered until collection consistency is established.
        $null = @(Read-VCFPage -Response $page -CollectionPage)
        $meta = $page.pageMetadata
        if ($null -eq $expectedPages) { $expectedPages=$meta.totalPages; $expectedElements=$meta.totalElements }
        if ($meta.totalPages -ne $expectedPages -or $meta.totalElements -ne $expectedElements -or
            -not $seen.Add([long] $meta.pageNumber)) { throw 'Inconsistent or repeated export page.' }
    }
    if ($Pages.Count -ne $expectedPages) { throw 'Missing export pages.' }
    foreach ($page in ($Pages | Sort-Object { $_.pageMetadata.pageNumber })) {
        foreach ($entry in $page.elements) { $rows.Add($entry) }
    }
    if ($rows.Count -ne $expectedElements) { throw 'Incomplete export record count.' }
    $rows.ToArray()
}
function Assert-VCFJsonNode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Text.Json.JsonElement] $Node)
    if ($Node.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Node.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'Duplicate or case-colliding JSON property.' }
            Assert-VCFJsonNode -Node $property.Value
        }
    } elseif ($Node.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Node.EnumerateArray()) { Assert-VCFJsonNode -Node $item }
    }
}
function Read-VCFJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Path)
    if ($Path -match '^(?:\\\\|//|[a-z]+://)') { throw 'Use a local JSON file.' }
    $full = [IO.Path]::GetFullPath($Path)
    if ($IsWindows -and [IO.DriveInfo]::new([IO.Path]::GetPathRoot($full)).DriveType -eq [IO.DriveType]::Network) { throw 'Network drives are not allowed.' }
    $file = [IO.FileInfo]::new($full)
    if (-not $file.Exists -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Expected a local regular file.' }
    $directory = $file.Directory
    while ($null -ne $directory) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Symbolic-link paths are not allowed.' }
        $directory = $directory.Parent
    }
    if ($file.Length -eq 0 -or $file.Length -gt 16777216) { throw 'JSON size must be between 1 byte and 16 MiB.' }
    $stream = [IO.FileStream]::new($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        if ($stream.Length -eq 0 -or $stream.Length -gt 16777216) { throw 'JSON size must be between 1 byte and 16 MiB.' }
        $bytes = [byte[]]::new([int] $stream.Length)
        $stream.ReadExactly($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($json.Length -gt 0 -and $json[0] -eq [char] 0xfeff) { $json=$json.Substring(1) }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth=64
    $document = [System.Text.Json.JsonDocument]::Parse([string] $json, $options)
    try { Assert-VCFJsonNode -Node $document.RootElement } finally { $document.Dispose() }
    $parsed = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $json -Depth 64 -NoEnumerate -ErrorAction Stop
    return ,$parsed
}
function Read-VCFExport {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $Path)
    $parsed=Read-VCFJson -Path $Path
    if ($parsed -is [array]) { return Read-VCFCollection -Pages $parsed }
    Read-VCFPage -Response $parsed
}
Export-ModuleMember -Function Read-VCFJson, Assert-VCFSuccessObject, Read-VCFPage, Read-VCFCollection, Read-VCFExport, Assert-VCFField, ConvertTo-VCFTimestamp
