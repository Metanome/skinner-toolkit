@echo off
setlocal

:: TurboBoostManager Compile Script
:: Compiles TurboBoostManager.ps1 to .exe using ps2exe

echo.
echo ============================================
echo   TurboBoostManager Compiler
echo ============================================
echo.

set "SCRIPT_DIR=%~dp0"
set "SOURCE=%SCRIPT_DIR%TurboBoostManager.ps1"
set "OUTPUT=%SCRIPT_DIR%TurboBoostManager.exe"
set "ICON=%SCRIPT_DIR%TurboBoostManager.ico"

:: Check if source exists
if not exist "%SOURCE%" (
    echo [ERROR] Source not found: %SOURCE%
    goto :error
)

echo Source:  %SOURCE%
echo Output:  %OUTPUT%
echo.

:: Run ps2exe via PowerShell 7 (pwsh) since that's where the module is installed
echo Compiling...
echo.

pwsh -NoProfile -ExecutionPolicy Bypass -Command ^
    "if (-not (Get-Module -ListAvailable -Name ps2exe)) { " ^
    "    Write-Host 'Installing ps2exe module...' -ForegroundColor Yellow; " ^
    "    Install-Module ps2exe -Scope CurrentUser -Force " ^
    "}; " ^
    "$params = @{ " ^
    "    InputFile = '%SOURCE%'; " ^
    "    OutputFile = '%OUTPUT%'; " ^
    "    NoConsole = $false; " ^
    "    RequireAdmin = $true; " ^
    "    Title = 'Turbo Boost Manager'; " ^
    "    Description = 'Control CPU Processor Performance Boost Mode'; " ^
    "    Company = 'Dr. Skinner'; " ^
    "    Product = 'Turbo Boost Manager'; " ^
    "    Copyright = 'Copyright (c) 2026 Dr. Skinner. GPLv3 License.'; " ^
    "    Version = '1.0.0.0' " ^
    "}; " ^
    "if (Test-Path '%ICON%') { $params.IconFile = '%ICON%' }; " ^
    "Invoke-PS2EXE @params"

if %ERRORLEVEL% neq 0 goto :error

:: Verify output
if exist "%OUTPUT%" (
    echo.
    echo ============================================
    echo   [SUCCESS] Compilation complete!
    echo ============================================
    echo   Output: %OUTPUT%
    echo.
) else (
    goto :error
)

goto :end

:error
echo.
echo [ERROR] Compilation failed!
echo.

:end
pause
