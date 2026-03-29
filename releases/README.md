# releases

This folder is for local release-ready outputs.

Right now it is mainly used for the packaged Windows download:

- `releases/windows/FlightTracker-Windows.zip`
- `releases/windows/FlightTracker/`

Why it is ignored:

- it contains generated binaries
- the files are large
- they should be published through GitHub Releases, not committed to source control

The Windows packaging script writes here by default:

- `scripts/Package-FlightTracker-Windows.ps1`
