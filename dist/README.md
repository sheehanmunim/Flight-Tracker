# dist

This folder is for generated build outputs.

Examples:

- Mac app bundles and DMGs
- other release artifacts created by packaging scripts or CI

Windows packaged downloads now go to:

- `releases/windows/`

Why it is mostly ignored:

- the files here are built from source and can be recreated
- they are often very large
- they change often and create noisy commits
- they do not belong in normal source control history

Where downloads should come from:

- GitHub Actions build artifacts
- GitHub Releases

In this repo, the packaging workflow is:

- `.github/workflows/build-release-artifacts.yml`

The Windows packaging script writes outputs here:

- `scripts/Package-FlightTracker-Windows.ps1`

The Mac packaging script writes outputs here:

- `macOS/Build-FlightTracker-MacApp.sh`
