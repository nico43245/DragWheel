# Security policy

## Supported versions

Security fixes go into the latest release.

## Reporting a vulnerability

Please report it privately with GitHub's **[Report a vulnerability](../../security/advisories/new)** button on this repository. Please don't open a public issue. You'll get a reply within a week.

## How releases are produced

- Every release is built by the [release workflow](.github/workflows/release.yml) on GitHub-hosted runners from the tagged source. Nothing is built on a personal machine.
- The workflows use no secrets. Third-party GitHub Actions are pinned to exact commit SHAs, and Dependabot proposes updates.
- Each release includes `SHA256SUMS.txt`. Public releases also carry a signed build-provenance attestation:
  ```bash
  gh attestation verify <downloaded file> --repo nico43245/DragWheel
  ```
- The background-removal model (`u2netp.onnx`) is downloaded during the build and verified against a fixed SHA-256 checksum.
- The apps aren't signed with a paid Apple Developer ID or a Windows code-signing certificate, so macOS and Windows ask you to confirm the first launch. The README explains how.
