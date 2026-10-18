# Validation

## What has been checked

The public candidate has **256 Pester cases** using command doubles and fictional fixtures, plus **13 standard-library Python tests** for packaging, scope and self-contained documentation. Configured PSScriptAnalyzer runs on scripts/helpers and examples. Gitleaks scans the source tree, complete source history and the generated candidate with full redaction. Logs and scanner reports remain outside the distribution.

Locally exercised tools: PowerShell 7.6.7/Linux x64, Pester 6.2.0, PSScriptAnalyzer 1.25.0, Python 3.14.7 and Gitleaks 8.30.1. The complete offline demo runs without PowerCLI/Pester in an isolated user/network namespace; its HTML matches the fictional reference and overwrite is rejected. These checks do not constitute new VMware functional validation. Earlier limited real results remain in [the per-tool matrix](docs/TOOL-VALIDATION-MATRIX.md) and [compatibility summary](docs/COMPATIBILITY.md).

## Reproduce locally

Using approved existing dependencies from the complete source/candidate directory:

```powershell
./tests/Invoke-Validation.ps1
$issues = @(Invoke-ScriptAnalyzer -Path ./examples -Recurse -Settings ./PSScriptAnalyzerSettings.psd1)
if ($issues.Count) { throw 'Example analysis failed.' }
```

```bash
python3 -B -m unittest discover -s tests -p 'test_*.py'
python3 -B tools/check_public_content.py
gitleaks dir . --redact=100
```

Run `gitleaks git . --log-opts=--all --redact=100` only in a full Git source checkout. Use restricted outside-Git paths for any logs. The public suite deliberately excludes real infrastructure data and observation-dependent tests; the local review tree retains those separately, so its 254-case result is not the public suite's count. No test opens a VMware connection or changes host configuration.

The public-content check validates the positive file set, relative Markdown links and plain Markdown document references, without fetching external URLs. Package verification checks exact files and all SHA-256 values; use Python `-B` to avoid adding bytecode caches. Git is needed for one temporary-repository test, not for history-free package verification.

## Hosted GitHub Actions workflow

The workflow uses `ubuntu-24.04`, read-only repository permission, checkout v7.0.1 pinned to `3d3c42e5aac5ba805825da76410c181273ba90b1` with persisted credentials disabled, and a 15-minute limit. The official release tag resolves to that GitHub-verified commit; its action manifest uses Node.js 24. No PowerCLI, VMware credentials, live connections, publication or artifact upload is configured.

The original [hosted run](https://github.com/danielfuentespl/vmware-community-toolkit/actions/runs/39130485116) passed with 251 Pester and ten Python cases. Current commands include warning-stream and dependency-integrity regressions. See [current workflow runs](https://github.com/danielfuentespl/vmware-community-toolkit/actions/workflows/validate.yml) for the result associated with each commit; a successful mock run is not new VMware functional validation.

`tools/install_ci_dependencies.py` downloads only Pester **6.2.0** and PSScriptAnalyzer **1.25.0** from the official PSGallery HTTPS package API. SHA-256 locks are checked before ZIP parsing, extraction or module import; package identity and absence of unreviewed NuGet dependencies are also checked. Both packages are verified before creating a fresh user-owned module directory under RUNNER_TEMP, added explicitly to PSModulePath. Nothing is installed globally. Existing module directories are never overwritten. Versions and hashes must be reviewed together when updating dependencies. Local tests verify rejection of tampered content, wrong identity, unreviewed dependencies and unsafe archive paths.

On 2026-10-18 the locked package bytes also matched the gallery's SHA-512 metadata, Authors and ProjectUrl for [Pester](https://www.powershellgallery.com/packages/Pester/6.2.0) and [PSScriptAnalyzer](https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0). A digest locks reviewed bytes; metadata from the same gallery is not an independent publisher signature or complete dependency audit. The packages retain their own licenses and are not bundled or relicensed as toolkit code. See Microsoft's [manual package download guidance](https://learn.microsoft.com/en-us/powershell/gallery/how-to/working-with-packages/manual-download).

Official references: [Ubuntu runner software](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md) and [checkout release](https://github.com/actions/checkout/releases/tag/v7.0.1). The runner provides pwsh, Python and Git. Runner image updates and Gallery availability remain external inputs; this is reproducible test logic with locked test packages, not a hermetic runtime image or vendor compatibility claim.

Standalone VMware readers treat provider warnings as failures using WarningAction Stop and suppress the original warning stream. Errors retain stable toolkit IDs and buffered queries emit no partial success records. This deliberately avoids reporting a warning-limited inventory as complete; inspect issues privately and keep all real execution logs outside Git. Normal result objects still contain infrastructure metadata. No provider warnings or errors should be pasted into public issues without sanitization.

## Reporting real results

Use [community testing](docs/COMMUNITY-TESTING.md) and [the result template](docs/TEST-RESULT-TEMPLATE.md). Keep static analysis, simulation, client rendering and authorized functional observations separate. No VCF deployment is functionally validated. Scanners cannot prove absence of every secret or resolve credentials exposed elsewhere.
