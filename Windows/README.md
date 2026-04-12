# Windows

This folder contains the Windows packaging files.

Most people should start from the repo root with:

- `Windows-EXE.cmd`

It contains:

- `Build-FlightTracker-Windows.ps1`: build the Windows package folder and installer
- `FlightTracker-Installer.iss`: Inno Setup definition for the Windows installer

Source launchers live at the repo root:

- `Browser.cmd`
- `Windows-EXE.cmd`

Generated Windows download outputs go to:

- `dist/windows/FlightTracker-Setup.exe`
- `dist/windows/FlightTracker/`

If `Inno Setup 6` is installed, the build script creates `FlightTracker-Setup.exe`.
Without it, the build still creates the unpacked app folder.
