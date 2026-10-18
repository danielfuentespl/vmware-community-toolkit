# Validation

## What has been checked

The public candidate has **251 Pester cases** using command doubles and fictional fixtures, plus **ten standard-library Python tests** for packaging, scope and self-contained documentation. Configured PSScriptAnalyzer runs on scripts/helpers and examples. Gitleaks scans the source tree, complete source history and the generated candidate with full redaction. Logs and scanner reports remain outside the distribution.

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

## Prepared GitHub Actions workflow

The workflow uses `ubuntu-24.04`, read-only repository permission, checkout pinned to a commit with persisted credentials disabled, and a 15-minute limit. It installs Pester **6.2.0** and PSScriptAnalyzer **1.25.0** in the runner's CurrentUser scope from PSGallery, imports those exact versions, logs runtime/module versions, runs PowerShell/Python/content checks and the fictional demo. No PowerCLI, VMware credentials, live connections, publication or artifact upload is configured.

Official references checked for preparation: [Ubuntu runner software](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md), [Pester package](https://www.powershellgallery.com/packages/Pester/6.2.0), [analyzer package](https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0) and [checkout release](https://github.com/actions/checkout/releases/tag/v4.2.2). The runner provides pwsh, Python and Git; test modules are version-pinned. **A hosted GitHub run has not occurred.** Only its test commands were exercised locally with existing modules; package-install steps were reviewed, not executed here. Runner image updates and Gallery availability remain external inputs, so this is reproducible test logic rather than a hermetic runtime image or vendor compatibility claim. Review the first hosted run and record its versions before claiming hosted validation.

## Reporting real results

Use [community testing](docs/COMMUNITY-TESTING.md) and [the result template](docs/TEST-RESULT-TEMPLATE.md). Keep static analysis, simulation, client rendering and authorized functional observations separate. No VCF deployment is functionally validated. Scanners cannot prove absence of every secret or resolve credentials exposed elsewhere.
