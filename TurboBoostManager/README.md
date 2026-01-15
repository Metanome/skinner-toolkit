# TurboBoostManager

A menu-driven PowerShell utility to control Windows Processor Performance Boost Mode (Turbo Boost).

## Features
- View and change boost modes for AC (plugged in) and DC (battery)
- Detects OEM software conflicts (Lenovo Vantage, Dell Power Manager, etc.)
- Toggle visibility of the setting in Windows Power Options

## Usage
Run as Administrator:
```powershell
.\TurboBoostManager.ps1
```

Or use the compiled executable: 
```powershell
TurboBoostManager.exe
```

## Building

To compile the `.ps1` to `.exe`, run:
```cmd
compile.cmd
```
Requires PowerShell 7 (`pwsh`) and the `ps2exe` module (auto-installed if missing).

## Requirements
- Windows 10/11
- Administrator privileges