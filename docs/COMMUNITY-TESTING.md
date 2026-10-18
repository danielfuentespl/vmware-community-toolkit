# Independent laboratory testing

The [per-tool matrix](TOOL-VALIDATION-MATRIX.md) summarizes limited reviewed observations. They do not certify universal minimum roles, positive ESXi 9 VM cases or other installations. Real community tests require an explicitly authorized lab, approved dependencies, trusted TLS and privately protected evidence. MIT permits reuse of original included material; submitting private evidence is not implied.

1. Run offline validation and the synthetic examples first. Record commit, OS/architecture, PowerShell, Pester and analyzer versions.
2. Review [setup](GETTING-STARTED.md), [the first-session procedure](VCENTER-FIRST-RUN.md) and each selected tool's Get-Help. Obtain explicit authorization for target, endpoint type (vCenter or direct ESXi), account privileges, read operations, evidence location and time window. Installation needs separate approval. Never attach credentials to a report.
3. Install/import only approved official modules and record exact versions. Keep normal TLS certificate/hostname validation; repair trust rather than bypassing validation. Use credentials in memory. Never provide a password as command-line text.
4. In an authorized PowerShell session, run the runner below. It executes only the three read reports and saves restricted aggregate evidence outside Git. Replace placeholders privately; do not paste filled commands into public issues. No DNS mutation is allowed.

```powershell
$credential = Get-Credential
./scripts/Lab/Invoke-ToolkitLabValidation.ps1 -Connect -VIServer '<authorized-target>' -EndpointType vCenter -Credential $credential -EvidenceDirectory '<private-local-directory-outside-git>'
Remove-Variable credential
```

For direct ESXi, use -EndpointType ESXi and record that scope separately; vCenter-wide inventory cannot be inferred. Check exact runner parameter spelling with Get-Help before use. The auxiliary harness itself remains functionally unverified; review its offline preflight before separately authorizing connection. DNS testing is optional, separately authorized, manual and -WhatIf only; review Get-Help for the explicit DNS preview lock and retain the hard write lock.

5. Compare counts and selected values privately with the same account and scope in the client; distinguish hidden objects from empty inventory. Exercise missing privileges, no snapshots/no matches and partial failure only within authorized read-only boundaries. Never change infrastructure to manufacture a failure. Record whether cleanup succeeded.
6. For VCF, obtain JSON exports by a separately authorized, documented process matching the actual product's official contract. Record exact product/API version and per-page capture method privately; process complete exports locally with -Path. Do not infer current health from historical SoS jobs, trust from certificate dates, or full BOM from manager versions.
7. Copy TEST-RESULT-TEMPLATE.md, replace any identifiers with unrelated fictional labels, strip raw messages/paths/IPs/usernames and review manually. Share only approved aggregate results and a commit reference through a channel you choose. Include failures and unknowns. Do not upload raw exports/evidence. A result applies only to the recorded combination, not all VMware versions.

Real validation is pending until evidence is reviewed; do not change matrix status on the strength of an unreviewed report.
