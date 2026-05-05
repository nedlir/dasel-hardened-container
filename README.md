# dasel v3.3.1 hardened container

This is a melange package and apko container image for [dasel v3.3.1](https://github.com/TomWright/dasel/releases/tag/v3.3.1) with a build-time patch for [CVE-2026-33320](https://github.com/TomWright/dasel/security/advisories/GHSA-4fcp-jxh7-23x8) (unbounded YAML alias expansion). The image is built entirely from a locally-produced APK - no prebuilt upstream image is used.

## Prerequisites

| Tool    | Tested version                                                                                                             | Purpose                                                 |
| ------- | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Docker  | 29.3.1                                                                                                                     | Container runtime, runs melange/apko via `compose.yaml` |
| melange | 0.50.5 (Docker image `cgr.dev/chainguard/melange@sha256:b6f11bb45a6090c182986028fd2249fb1a18dcb6e173c4ce001dd3fb4cb1dd71`) | APK package builder                                     |
| apko    | 1.2.10 (Docker image `cgr.dev/chainguard/apko@sha256:20dfc1f5e3461b5eaf3279f762cd4bf86c7f3635d2a9642f905cf583525f9ee6`)    | OCI image builder                                       |

- Architecture: **x86_64** only
- Internet access required for initial build (fetches source tarball, Go modules, Wolfi packages)

### Windows requirements

All build and load commands work from any terminal (PowerShell, CMD, or bash). One step still requires a Unix shell:

- `bash tests/test.sh` — the test script uses bash and coreutils (`timeout`, `grep`, `sed`)

Install **Git Bash** (ships with [Git for Windows](https://git-scm.com/download/win)) before running the image tests.

## Project Structure

```
.
├── melange/
│   ├── dasel.yaml
│   └── CVE-2026-33320.patch
├── apko/
│   └── dasel.yaml
├── tests/
│   └── test.sh
├── compose.yaml
├── keys/                       # Generated, gitignored
│   ├── melange.rsa
│   └── melange.rsa.pub
├── sbom/                       # Generated, gitignored
│   ├── sbom-x86_64.spdx.json
│   └── sbom-index.spdx.json
├── packages/                   # Generated, gitignored
│   └── x86_64/
│       ├── dasel-3.3.1-r0.apk
│       └── APKINDEX.tar.gz
└── README.md
```

## Build

```bash
# 1. Generate signing keys (one-time)
docker compose run --rm melange keygen keys/melange.rsa

# 2. Build the APK package (fetches source, applies CVE patch, compiles)
docker compose run --rm melange build melange/dasel.yaml --arch x86_64 --signing-key keys/melange.rsa

# 3. Build the OCI image (consumes the local APK)
docker compose run --rm apko build apko/dasel.yaml dasel:3.3.1 dasel.tar --arch x86_64 --sbom-path sbom/
```

Step 2 automatically generates and signs `packages/x86_64/APKINDEX.tar.gz`.

## Run

After loading the image, run dasel:

```bash
docker load --input dasel.tar

# Example: query a JSON file
echo '{"name": "dasel"}' | docker run --rm \
  --read-only \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -i dasel:3.3.1-amd64 \
  -i json 'name'
```

These flags enforce the runtime layer of the defense-in-depth strategy described in [Image Hardening](#image-hardening): an immutable root filesystem, zero Linux capabilities, and no privilege escalation paths.

## Test

```bash
docker compose run --rm melange test melange/dasel.yaml --arch x86_64
```

**Image tests:**

```bash
# Load the image (works from PowerShell, CMD, or bash)
docker load --input dasel.tar

# Run the test script (requires Git Bash on Windows)
bash tests/test.sh
```

The test script verifies:

- Image loads and `dasel version` reports `v3.3.1`
- JSON key extraction (`-i json 'test'`)
- JSON-to-YAML conversion (`-i json -o yaml --root`)
- CVE patch: malicious billion-laughs YAML triggers `"yaml expansion budget exceeded"` instead of hanging

## CVE-2026-33320 Fix

The vulnerability allows unbounded CPU/memory consumption via exponentially nested YAML aliases (billion laughs attack). The patch at `melange/CVE-2026-33320.patch` adds two safeguards to dasel's YAML reader: an expansion depth limit (32) that caps recursive alias nesting, and an expansion budget (1000) that caps total alias dereferences per document. When either limit is hit, decoding returns an error immediately.

## Security, Reproducibility & Minimality

- **Security**: CVE-2026-33320 patched at build time. All packages are signed. Image contains only 3 APK packages (wolfi-baselayout, ca-certificates-bundle, dasel)
- **Reproducibility**: Declarative YAML for both package and image. Source tarball pinned by SHA256. All tool versions documented. Go binary built with `-trimpath` to strip local build paths
- **Minimality**: No shell, no package manager in the final image - just the dasel binary, CA certificates, and baselayout

### Image Hardening

The image applies defense-in-depth beyond minimal packaging:

| Layer   | Measure                            | Effect                                              |
| ------- | ---------------------------------- | --------------------------------------------------- |
| Build   | Non-root user (UID 65532)          | Container process never runs as root                |
| Build   | `-s -w` ldflags + auto `-trimpath` | Stripped binary, no local path leakage              |
| Build   | 3 packages only                    | Minimal attack surface, no shell or package manager |
| Runtime | `--read-only`                      | Immutable root filesystem                           |
| Runtime | `--cap-drop=ALL`                   | Zero Linux capabilities                             |
| Runtime | `--no-new-privileges`              | Prevents privilege escalation via setuid/setgid     |

## Vulnerability Scanning

The built image (`dasel.tar`) was scanned with industry-standard tools to validate security posture beyond the CVE patch itself.

### Syft (SBOM generation)

Syft extracted **36 packages** from the image by inspecting the Go binary's module metadata:

- **3 APK packages**: `wolfi-baselayout` 20230201-r29, `ca-certificates-bundle` 20260413-r0, `dasel` 3.3.1-r0
- **32 Go modules**: including `go.yaml.in/yaml/v4`, `github.com/hashicorp/hcl/v2`, `github.com/pelletier/go-toml/v2`, `github.com/goccy/go-json`, `github.com/charmbracelet/bubbletea`, `golang.org/x/sys`, `golang.org/x/text`, `stdlib` go1.25.9, and 25 more
- **19 files inventoried**: `/usr/bin/dasel`, `/etc/ssl/certs/ca-certificates.crt`, APK DB, per-package SBOMs, and baselayout config files

### Grype (vulnerability scanner)

The SBOM that I generated what inspected with Grype with no other vulnerabilities found across any of the 32 Go modules or 3 APK packages.

## Submission

### Assumptions

- **x86_64 only** - single-arch build. Multi-arch would require additional `--arch` flags
- **Throwaway signing keys** - generated locally and gitignored. In a production setup, private signing keys should be stored in a secrets manager, not on the local filesystem. even if gitignored files can be exposed through backup tools, container volume mounts, or a compromised workstation.
- **Wolfi OS dependency** - the build and final image depend on Wolfi packages (`busybox`, `go`, `ca-certificates-bundle`). If a vulnerability is discovered in any of those upstream packages, it would affect this image as well. Keeping Wolfi packages up to date or subscribing to their security advisories would be necessary in production
- **Docker Compose wrappers** - melange and apko run as Docker containers via `compose.yaml`. This was developed on Kali 2025.3 and verified on Windows 10 with Docker Desktop 29.3.1
- **Test script requires bash** - `tests/test.sh` uses `timeout` (coreutils) and Docker CLI. All other commands are pure `docker` and work from PowerShell or CMD. On Windows, run the test script from Git Bash (see [Windows requirements](#windows-requirements))

### SBOM Coverage Gap

apko automatically generates SPDX SBOMs at build time into the `sbom/` folder (`sbom/sbom-x86_64.spdx.json`, `sbom/sbom-index.spdx.json`). These track the 3 installed APK packages with versions, CPEs, source provenance, and Melange build definition references. However, they do **not** include Go module dependencies compiled into the `dasel` binary. I decided to scan them and used Syft to close this gap by extracting all 32 Go modules from the binary's embedded metadata.

For prod environment there should be some automation of the SBOM extraction that would poll periodically. Then maybe attach the SBOM results with something like [https://github.com/nedlir/CVEnotifier](https://github.com/nedlir/CVEnotifier) I wrote in Golang to find novel vulnerabilities in the supply chain.

### Commands run and results

| Command                                                                                                    | Result                                                                                   |
| ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `docker compose run --rm melange keygen keys/melange.rsa`                                                  | Passed                                                                                   |
| `docker compose run --rm melange build melange/dasel.yaml --arch x86_64 --signing-key keys/melange.rsa`    | Passed - patch applied (7/7 hunks), APK produced                                         |
| `docker compose run --rm melange test melange/dasel.yaml --arch x86_64`                                    | Passed - version, JSON key extraction, JSON array access                                 |
| `docker compose run --rm apko build apko/dasel.yaml dasel:3.3.1 dasel.tar --arch x86_64 --sbom-path sbom/` | Passed - 3 packages installed, OCI tarball produced                                      |
| `docker load --input dasel.tar`                                                                            | Passed - `dasel:3.3.1-amd64` loaded                                                      |
| `bash tests/test.sh`                                                                                       | Passed - all tests (version, key extraction, format conversion, YAML aliases, CVE patch) |
| `docker run --rm -v ... anchore/grype:latest /work/dasel.tar`                                              | Passed - 1 finding (expected false positive for the patched CVE)                         |
| `docker run --rm -v ... anchore/syft:latest /work/dasel.tar`                                               | Passed - 36 packages cataloged (3 APK + 32 Go + 1 stdlib)                                |

### Future improvements

- **Multi-arch builds** - support multiple architectures for building this container.

- **CI/CD pipeline** - automate build + test in GitHub Actions with melange/apko container actions

- **Go-level SBOM in melange** - run `syft` during the melange build pipeline and embed the Go-module SBOM alongside the APK
