# Fictional report demonstration — local only

All content is invented from bundled fixtures. This is a toolkit-generated HTML document, **not a screenshot of VMware software, a real environment or a successful functional VMware test**. It contains 15 supplied data sections: seven original report models, five ESXi observations and three source-specific VCF collections. No central VMware execution occurred, so no execution-status collection is fabricated.

- [Portable HTML](community-report.html)
- [Desktop capture, 1440 × 1000](community-desktop.png)
- [Narrow-window capture, 500 × 1000](community-narrow.png)
- [Artifact/fixture hashes and capture metadata](manifest.json)

## Reproduce the HTML

From the repository root using existing PowerShell, choose a new file in an existing local directory:

```powershell
$demoPath = Join-Path ([IO.Path]::GetTempPath()) ('vmware-toolkit-demo-' + [guid]::NewGuid().ToString('N') + '.html')
$demo = ./examples/Invoke-CommunityOfflineDemo.ps1 -OutputPath $demoPath
$demo.Report
```

The capture/evaluation date is fixed by the fictional fixtures. The HTML content is deterministic for this input and code; its receipt path varies. Existing files are refused. Inventory/snapshot/ESXi inputs are output-model fixtures, not live provider calls. VCF adapters, comparison and rendering do execute locally. Do not replace fixtures with real exports for public screenshots.

## Capture method used

Existing Chromium **152.0.7977.82 (Arch Linux)** rendered the file directly through `file://`. No browser, driver, fonts or other component was installed. Final captures were created inside a fresh Linux user/network namespace using `unshare --user --map-current-user --net`. Its only interface was loopback, down; there was no external network interface or route. Separate temporary profiles avoided existing account/browser state. Proxy/DNS restrictions and disabled background networking were additional controls; isolation was the network boundary. Net logs recorded zero successful socket connections.

The initial capture attempt outside the namespace recorded a failed Chromium IPv6 connectivity probe despite background/DNS/proxy restrictions. It did not establish a connection. Those initial PNGs were replaced by the isolated captures; logs remain private rather than packaged. A browser flag alone is not asserted to guarantee network isolation.

For an optional repeat on an existing Linux/Chromium installation, substitute absolute paths for a trusted fictional HTML file, a new PNG path and a fresh temporary profile. Nothing is installed:

```bash
unshare --user --map-current-user --net chromium \
  --headless --disable-gpu --disable-background-networking \
  --disable-component-update --disable-extensions --disable-sync --disable-quic \
  --no-first-run --no-default-browser-check --metrics-recording-only \
  --host-resolver-rules='MAP * ~NOTFOUND' --proxy-server='http://127.0.0.1:9' \
  --user-data-dir=/tmp/toolkit-capture-fresh-profile \
  --window-size=1440,1000 --hide-scrollbars \
  --screenshot=/tmp/new-fictional-desktop.png \
  file:///absolute/path/to/fictional-report.html
```

Use another fresh profile and `--window-size=500,1000` for a narrow-window capture. Check that output paths do not already exist: Chromium's screenshot flag itself is not an exclusive-write API. If user/network namespaces are unavailable, do not silently fall back to an online browser. This optional procedure is Linux-specific and not part of toolkit runtime dependencies.

The PNGs are actual viewport captures, without compositing or image generation. Visual review confirmed readable desktop layout and narrow-window wrapping. The narrow image shows the upper report only; it is not device emulation or proof that all report sections were visually inspected on mobile. Tables support local scrolling. Font/browser differences can change pixels; only the HTML determinism and packaged file hashes are asserted, not cross-machine PNG identity.

No raw browser profiles, net logs, private reports or real infrastructure exports are distributed. Screenshot filenames/metadata and the HTML were reviewed for fabricated-only content. Publication, license and distribution-rights approval remain pending even for these prepared assets.

## License and integrity

The original fictional HTML/PNG assets and source fixtures are covered by MIT, Copyright (c) 2026 Daniel Fuentes; retain LICENSE and the applicable notice. They are not VMware screenshots or infrastructure evidence. manifest.json preserves the original capture metadata/input hashes and separately records current input hashes after MIT notices. HTML regeneration is compared with the original bytes. Existing PNGs are unchanged; no new browser or VMware functional claim is made.
