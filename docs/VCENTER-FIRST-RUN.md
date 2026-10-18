# First authorized vCenter session

Use only with the environment owner's authorization, approved official modules and trusted TLS. [Setup](GETTING-STARTED.md), [tested limits](COMPATIBILITY.md) and [the evidence template](TEST-RESULT-TEMPLATE.md) provide prerequisites. This procedure is guidance, not an automatic connection.

1. Agree privately on target, time window, VM/host scope, read role and evidence directory outside Git. Do not share passwords or real names in issues. Start with Inventory, not All. Visibility and privileges must be verified with the target owner; read-only roles can still lack certificate, settings or snapshot-size access.
2. In an existing approved PowerShell session, check versions and commands without installing:

```powershell
$PSVersionTable
Get-Module -ListAvailable VMware.VimAutomation.Core | Select-Object Name,Version,Path
Get-Command Connect-VIServer,Disconnect-VIServer,Get-PowerCLIConfiguration,Set-PowerCLIConfiguration,Get-VM,Get-Datastore,Get-VMHost,Get-View -ErrorAction Stop
./scripts/Invoke-VMwareToolkit.ps1 -ListProfiles
./scripts/Invoke-VMwareToolkit.ps1 -ListChecks
```

3. Only after connection authorization, set fail-closed certificate handling for this session, check the effective policy and connect to the privately supplied approved DNS name. Stop on trust, hostname or certificate errors; do not bypass them. Credentials remain in memory:

```powershell
Set-PowerCLIConfiguration -Scope Session -InvalidCertificateAction Fail -Confirm:$false
Get-PowerCLIConfiguration
$credential = Get-Credential
$connection = Connect-VIServer -Server $approvedVCenter -Credential $credential -NotDefault -ErrorAction Stop
$credential = $null
try {
    $result = ./scripts/Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId $approvedOpaqueScope -Profile Inventory -VMName $approvedVMFilter -DatastoreName $approvedDatastoreFilter -HtmlPath $newPrivateHtmlPath
    $result | Select-Object State,Outcome,ExecutionCompleted,SourceExecutions,RealVmwareValidated
    $result.Checks | Select-Object Check,Requested,Status,State,RowCount,Message
} finally {
    Disconnect-VIServer -Server $connection -Confirm:$false
}
```

Variables above must be supplied privately; HTML parent must already exist in trusted local storage, outside Git, with restricted permissions. Use a new filename. Do not dump connection objects, credentials, tokens or raw exception records. WhatIf controls HTML creation only; it does not suppress read queries. The central runner cannot invoke the DNS write/preview tool.

4. Compare visible VM counts, power states, CPU and memory with the same vSphere Client scope, filters and capture time; compare datastore capacity in the same units. For subsequent separately approved Operations/Security checks review each tool's Get-Help and the [PowerCLI contracts](POWERCLI-CONTRACTS.md) / [ESXi contracts](ESXI-AUDIT-CONTRACTS.md). A missing/empty result does not prove health or visibility. Record discrepancies and permission denials privately; do not broaden privileges automatically.
5. Record PowerShell/OS, PowerCLI module versions, vCenter/ESXi versions/builds, scope, time/zone, selected checks, per-check states and sanitized error identifiers. Keep raw evidence private. Submit only reviewed fictionalized examples using the existing template. Mark actual execution separately from static analysis and mocks; one tested environment does not establish general release compatibility.
