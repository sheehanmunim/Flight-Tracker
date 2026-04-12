# Windows

This folder contains the Windows packaging files.

Most people should start from the repo root with:

- `Build-FlightTracker-Windows.cmd`

It contains:

- `Build-FlightTracker-Windows.ps1`: build the Windows package, ZIP, and installer
- `FlightTracker-Installer.iss`: Inno Setup definition for the Windows installer

Source launchers live at the repo root:

- `Run-FlightTracker-Windows.cmd`
- `Run-FlightTracker-Browser.cmd`

Generated Windows download outputs go to:

- `dist/windows/FlightTracker-Setup.exe`
- `dist/windows/FlightTracker-Windows.zip`
- `dist/windows/FlightTracker/`

If `Inno Setup 6` is installed, the build script creates `FlightTracker-Setup.exe`.
Without it, the script still creates the portable ZIP and unpacked app folder.
