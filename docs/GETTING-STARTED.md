# Installation and first use

This is a collection of scripts, not an installable PowerShell module. Keep the complete directory tree: runtime scripts depend on scripts/Private; offline demos depend on the bundled fictional tests/fixtures. Both READMEs, examples, tests, packaging tools and user documentation are included under MIT, Copyright (c) 2026 Daniel Fuentes. No runtime, PowerCLI module or development-tool binary is bundled.

Use a supplied complete candidate directory or a complete checkout of the public repository. The [public GitHub repository](https://github.com/danielfuentespl/vmware-community-toolkit) is available; no hosted release or installer is provided. A Git source checkout needs no distribution manifest; the verification command below applies only to a history-free package containing SHA256SUMS. All output paths should be outside the sealed candidate.

## 1. Verify a supplied distribution and start offline

From the root of a complete local candidate, using existing Python 3 if available:

```bash
python3 tools/build_offline_candidate.py . --verify
```

Verification needs no Git history, dependencies or network. It checks the exact file set and SHA-256, including unexpected extra files. A matching manifest proves internal integrity, not a trusted sender, ownership, a signature or publication approval. Keep the received package read-only; write outputs elsewhere. Full source builds, in contrast to verification, require Git and a clean committed source tree.

If PowerShell is absent, review Microsoft's official [Linux installation instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux) for an approved runtime/OS; this toolkit provides no runtime bootstrap. Then open a PowerShell session in that root. Tested runtime: PowerShell 7.6.7/Linux x64. PowerShell 7.4+ is the source target; Windows/macOS and other runtime releases have not been executed here.

```powershell
$PSVersionTable
./scripts/Invoke-VMwareToolkit.ps1 -ListProfiles
./scripts/Invoke-VMwareToolkit.ps1 -ListChecks
Get-Help ./scripts/Invoke-VMwareToolkit.ps1 -Full
$demoPath = Join-Path ([IO.Path]::GetTempPath()) ('toolkit-demo-' + [guid]::NewGuid().ToString('N') + '.html')
$demo = ./examples/Invoke-CommunityOfflineDemo.ps1 -OutputPath $demoPath
$demo.Inventory
$demo.Changes
$demo.Report
```

No PowerCLI, Pester, account or VMware endpoint is needed. The output parent must already exist; overwrites are refused. The demo displays fictional provider output models and actually executes offline comparison, seven VCF adapters and HTML rendering. It is simulation, not a VMware connection. Use the same complete tree for the individual [examples](../examples/README.md). No external browser assets or telemetry are required to read the HTML.

Python, Pester, PSScriptAnalyzer, Gitleaks and Chromium are not requirements for running the offline demo itself. Python verifies packages without Git; source builds and one Python boundary test also require an existing Git executable. Pester/analyzer/Gitleaks validate development; Chromium is optional for inspecting screenshots. No helper installs these dependencies.

## 2. Optional PowerCLI setup — future authorized action

Do not run an installation as part of the offline start. If an authorized user needs live reports, first review the current official [Broadcom guide](https://developer.broadcom.com/powercli/installation-guide), package provenance, module conflicts and the tested tuple below. The vendor guide describes VCF.PowerCLI; the toolkit used the smaller product-specific Core module and its dependencies. The full VCF bundle is not required by these reports. Nothing here upgrades or removes existing modules automatically.

Observed in the authorized lab, **not a vendor support certification**:

| Module | Installed version in the lab |
|---|---|
| VMware.VimAutomation.Core / Cis.Core / Common / Sdk | 13.5.1.25718932 each |
| VMware.Vcf.Sso / VMware.OpenAPI | 13.5.1.25718932 each |
| VMware.Vim | 9.1.0.25718932 |

Module/SDK versions do not identify the VMware server version. This exact set worked for the limited [per-tool observations](TOOL-VALIDATION-MATRIX.md); it is not a claim about every VMware release, Linux distribution, future Gallery dependency resolution or newest bundle.

These preparation commands query the official source only when a user elects to run them; they do not install anything by themselves:

```powershell
$ErrorActionPreference = 'Stop'
$gallery = Get-PSRepository -Name PSGallery -ErrorAction Stop
if ([uri]$gallery.SourceLocation -ne [uri]'https://www.powershellgallery.com/api/v2') {
    throw 'Unexpected package source.'
}
Find-Module -Name VMware.VimAutomation.Core -RequiredVersion '13.5.1.25718932' -Repository PSGallery |
    Select-Object Name, Version, Author, Dependencies
```

After package review and installation authorization, the normal Core command is:

```powershell
Install-Module -Name VMware.VimAutomation.Core -RequiredVersion '13.5.1.25718932' -Repository PSGallery -Scope CurrentUser -ErrorAction Stop
```

Review license/publisher/source prompts instead of accepting them in an unattended bootstrap. **RequiredVersion on Core does not lock transitive dependencies.** The table records the exact modules actually observed in the lab. Compare all installed/imported versions after resolving dependencies; a Core pin alone cannot recreate that closure. If your approved procedure requires an exact closure, review/pin every dependency before installing. Stop if resolution differs or existing modules conflict; do not silently migrate the user's setup. No sudo, AllUsers installation or blanket publisher/TLS bypass is part of this guide.

After the approved installation, inspect locally before a connection:

```powershell
Get-Module -ListAvailable VMware.VimAutomation.Core,VMware.VimAutomation.Cis.Core,VMware.OpenAPI,VMware.Vim,VMware.Vcf.Sso,VMware.VimAutomation.Common,VMware.VimAutomation.Sdk |
    Select-Object Name, Version
Import-Module VMware.VimAutomation.Core -RequiredVersion '13.5.1.25718932' -ErrorAction Stop
$required = 'Connect-VIServer','Disconnect-VIServer','Get-VM','Get-View','Get-Snapshot','Get-Datastore','Get-VMHost','Get-VMHostNetwork','Get-VMHostService','Get-VMHostFirewallException','Get-AdvancedSetting','Get-VIMachineCertificate'
Get-Command -Name $required -Module VMware.VimAutomation.Core -ErrorAction Stop |
    Select-Object Name, ModuleName, Version
```

These checks import vendor initialization code after review but do not connect. Gallery metadata/hashes are not cryptographic publisher verification. Linux Authenticode verification was unavailable in the lab; record any remaining assurance decision rather than implying a signature check passed. No execution-policy or certificate-store changes are required by the toolkit itself; follow local policy if the platform blocks execution.

## 3. Future authorized read-only run

This example has a deliberately nonexistent hostname. Replace it only after target/permission/TLS authorization. It is example syntax, not authorization to connect. The CA chain and hostname/IP SAN must validate; Session Fail rejects invalid certificates and does not create trust. Correct trust through an approved process, not by disabling TLS verification. Keep credentials in memory and raw results/HTML outside Git in a restricted directory.

```powershell
$credential = Get-Credential
$connection = $null
try {
    Set-PowerCLIConfiguration -Scope Session -InvalidCertificateAction Fail -ParticipateInCEIP:$false -Confirm:$false | Out-Null
    $connection = Connect-VIServer -Server 'vc.example.invalid' -Credential $credential -NotDefault -ErrorAction Stop
    $result = ./scripts/Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId 'approved-scope-01' -Profile Inventory
    $result.Checks | Select-Object Check, State, Reason, RowCount
    $result.Outcome
} finally {
    if ($null -ne $connection) {
        Disconnect-VIServer -Server $connection -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    $credential = $null
}
```

Keep the same opaque ScopeId only for captures of the same persistent endpoint/identity namespace. Direct ESXi uses EndpointType ESXi, but certificate checks remain unsupported there. For optional HTML, supply `-HtmlPath` with a new filename in an existing private directory outside Git; decline/WhatIf suppresses that local write, not the VMware read queries. Do not serialize a VIServer or PSCredential.

| Profile | Selection / important limit |
|---|---|
| Inventory | VMInventory, Tools, Datastores |
| Operations | Inventory plus snapshots/age, host health, DNS/NTP/time; default age threshold 7 days |
| Security | Certificates, HostSecurity, Firewall, Syslog, Time, AdvancedSettings |
| All | All fourteen allowlisted read checks; excludes DNS setter and VCF adapters |

Use `-Checks VMInventory,Tools` instead of a profile for an explicit allowlisted subset; do not combine Checks and Profile. The runner accepts no arbitrary script path. Source reuse/row budgets and upstream-memory limitations are documented in [CENTRAL-RUNNER.md](CENTRAL-RUNNER.md).

Outcome/State reports execution, not health or compliance. Empty snapshots cannot prove positive snapshot coverage. Unknown and NotRun are meaningful, and Security/All remained partial in the real lab. A scoped ReadOnly account worked for thirteen direct ESXi8 readers; an irreducible role and vCenter SSO minimum-role tests remain pending. Treat a restricted user's empty inventory as limited visibility unless completeness is established.

DNS preview remains separately locked to WhatIf and has no real functional validation; do not enable it as part of getting started. VCF tools accept local JSON only, not an implicit VCF connection. Recorded real coverage remains 41 PASS / 12 PARTIAL / 2 BLOCKED across 55 cumulative cases, not 55 new tests here. See [compatibility](COMPATIBILITY.md).

## 4. Development checks with already approved tools

```powershell
./tests/Invoke-Validation.ps1
Invoke-ScriptAnalyzer -Path ./examples -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

```bash
python3 -B -m unittest discover -s tests -p 'test_*.py'
python3 -B tools/check_public_content.py
gitleaks dir . --redact=100 --no-banner
```

Pester 6.2.0, PSScriptAnalyzer 1.25.0 and Gitleaks 8.30.1 are the executed test-tool versions; these tests do not establish other versions. Scan full Git history only in the source repository, not the history-free staging directory:

```bash
gitleaks git . --log-opts=--all --redact=100 --no-banner
```

A history-free package is sufficient to run the scripts and demo. With the approved development tools (including Git for the temporary packaging-test fixture), it also runs local tests; it cannot build a source-identified candidate without the source Git history. Public issue/PR templates are included in the GitHub repository. MIT permits reuse of the original included materials with notice retention; security disclosure and any publication action remain separate responsibilities.
