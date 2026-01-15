#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Turbo Boost Manager - Control CPU Processor Performance Boost Mode
.DESCRIPTION
    A menu-driven utility to view and change the Windows Processor Performance Boost Mode
    (Turbo Boost) settings for both AC (plugged in) and DC (battery) power states.
.NOTES
    Author: Dr. Skinner
    Requires: Administrator privileges
#>

# Mode descriptions (used when system doesn't provide friendly names)
$ModeDescriptions = @{
    "Disabled" = "Turbo Boost OFF - CPU stays at base frequency"
    "Enabled" = "Turbo Boost ON - Standard boost behavior"
    "Aggressive" = "Proactive boosting for maximum performance"
    "Efficient Enabled" = "Boost with power efficiency focus"
    "Efficient Aggressive" = "Aggressive boost with efficiency considerations"
    "Aggressive At Guaranteed" = "Aggressive boost hitting guaranteed speeds"
    "Efficient Aggressive At Guaranteed" = "Efficient aggressive at guaranteed speeds"
}

# Track visibility state (start with visible so script can work)
$script:SettingHidden = $false
$script:BoostModes = @{}

function Ensure-SettingVisible {
    powercfg.exe -attributes sub_processor perfboostmode -attrib_hide 2>$null
}

function Hide-Setting {
    powercfg.exe -attributes sub_processor perfboostmode +attrib_hide 2>$null
}

function Get-SupportedBoostModes {
    $modes = @{}
    
    try {
        $activeScheme = powercfg /getactivescheme
        if ($activeScheme -match ":\s*([a-f0-9-]+)") {
            $schemeGuid = $Matches[1]
        } else {
            return $modes
        }
        
        $queryLines = powercfg /query $schemeGuid sub_processor perfboostmode 2>$null
        
        $currentIndex = $null
        foreach ($line in $queryLines) {
            if ($line -match "Possible Setting Index:\s*(\d+)") {
                $currentIndex = [int]$Matches[1]
            }
            if ($null -ne $currentIndex -and $line -match "Possible Setting Friendly Name:\s*(.+)") {
                $friendlyName = $Matches[1].Trim()
                $description = if ($ModeDescriptions.ContainsKey($friendlyName)) { 
                    $ModeDescriptions[$friendlyName] 
                } else { 
                    "Mode $currentIndex" 
                }
                $modes[$currentIndex] = @{ Name = $friendlyName; Description = $description }
                $currentIndex = $null
            }
        }
    } catch {
        # Fallback to empty
    }
    
    return $modes
}

# Unhide at startup so we can read values
Ensure-SettingVisible

# Get supported modes from system
$script:BoostModes = Get-SupportedBoostModes

# Validate that boost setting exists
if ($script:BoostModes.Count -eq 0) {
    Write-Host ""
    Write-Host "  ERROR: Processor Performance Boost Mode not available!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  This could mean:" -ForegroundColor Yellow
    Write-Host "    - Your CPU doesn't support Turbo Boost / Precision Boost"
    Write-Host "    - The setting is locked by your BIOS/UEFI"
    Write-Host "    - Windows power management is restricted"
    Write-Host ""
    Write-Host "  Press any key to exit..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Check for common OEM power management software
function Test-OEMSoftware {
    $warnings = @()
    
    # Lenovo Vantage / Legion Zone
    # Services: ImControllerService (System Interface Foundation), LenovoVantageService, LZService (Legion Zone)
    $lenovoServices = Get-Service -Name "ImControllerService", "LenovoVantageService", "LZService" -ErrorAction SilentlyContinue
    if ($lenovoServices | Where-Object { $_.Status -eq 'Running' }) {
        $warnings += "Lenovo Vantage/Legion Zone is running - it may override your boost settings"
    }
    
    # Dell Power Manager / Optimizer / MyDell
    # Services: Dell Power Manager Service, Dell Optimizer
    $dellServices = Get-Service -Name "DellPowerManagerService", "Dell Optimizer Service", "DDVDataCollector" -ErrorAction SilentlyContinue
    if ($dellServices | Where-Object { $_.Status -eq 'Running' }) {
        $warnings += "Dell Power Manager/Optimizer is running - it may override your boost settings"
    }
    
    # ASUS Armoury Crate
    # Service: ArmouryCrateService (ArmouryCrate.Service.exe)
    $asusServices = Get-Service -Name "ArmouryCrateService", "AsusSystemDiagnosis" -ErrorAction SilentlyContinue
    if ($asusServices | Where-Object { $_.Status -eq 'Running' }) {
        $warnings += "ASUS Armoury Crate is running - it may override your boost settings"
    }
    
    # HP Command Center / Omen Gaming Hub
    # Services: HP Omen HSA, HP Application Enabling Services
    $hpServices = Get-Service -Name "HPSysInfoCap", "HpTouchpointAnalyticsService", "HPAppHelperCap" -ErrorAction SilentlyContinue
    if ($hpServices | Where-Object { $_.Status -eq 'Running' }) {
        $warnings += "HP Omen/Command Center is running - it may override your boost settings"
    }
    
    # MSI Center / Dragon Center
    # Services: MSI Central Service, MSI_VoiceControl_Service
    $msiServices = Get-Service -Name "MSI Central Service", "MSI_VoiceControl_Service" -ErrorAction SilentlyContinue
    if ($msiServices | Where-Object { $_.Status -eq 'Running' }) {
        $warnings += "MSI Center/Dragon Center is running - it may override your boost settings"
    }
    
    return $warnings
}

$script:OEMWarnings = Test-OEMSoftware

function Get-CurrentPowerSource {
    # Returns "AC" if plugged in, "DC" if on battery
    try {
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
        if ($null -eq $battery) {
            # Desktop PC - no battery, always AC
            return "AC"
        }
        # BatteryStatus: 1 = Discharging (on battery), 2 = AC Power
        if ($battery.BatteryStatus -eq 2) {
            return "AC"
        } else {
            return "DC"
        }
    } catch {
        return "AC"  # Default to AC if detection fails
    }
}

function Get-CurrentBoostMode {
    param (
        [string]$PowerType
    )
    
    try {
        $activeScheme = powercfg /getactivescheme
        if ($activeScheme -match ":\s*([a-f0-9-]+)") {
            $schemeGuid = $Matches[1]
        } else {
            return $null
        }
        
        $queryLines = powercfg /query $schemeGuid sub_processor perfboostmode 2>$null
        
        foreach ($line in $queryLines) {
            if ($PowerType -eq "AC" -and $line -match "Current AC Power Setting Index:\s*0x([0-9a-fA-F]+)") {
                return [Convert]::ToInt32($Matches[1], 16)
            }
            if ($PowerType -eq "DC" -and $line -match "Current DC Power Setting Index:\s*0x([0-9a-fA-F]+)") {
                return [Convert]::ToInt32($Matches[1], 16)
            }
        }
    } catch {
        return $null
    }
    return $null
}

function Get-ActivePlanName {
    $activeScheme = powercfg /getactivescheme
    if ($activeScheme -match "\((.+)\)") {
        return $Matches[1]
    }
    return "Unknown"
}

function Set-BoostMode {
    param (
        [int]$ModeValue,
        [bool]$ApplyToAC = $true,
        [bool]$ApplyToDC = $true
    )
    
    try {
        if ($ApplyToAC) {
            powercfg /setacvalueindex scheme_current sub_processor perfboostmode $ModeValue
        }
        if ($ApplyToDC) {
            powercfg /setdcvalueindex scheme_current sub_processor perfboostmode $ModeValue
        }
        powercfg /setactive scheme_current
        return $true
    } catch {
        return $false
    }
}

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "                    TURBO BOOST MANAGER" -ForegroundColor Yellow
    Write-Host "            Control CPU Performance Boost Mode" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    
    # Show OEM warnings if any
    if ($script:OEMWarnings.Count -gt 0) {
        Write-Host ""
        Write-Host "  WARNING:" -ForegroundColor Yellow
        foreach ($warning in $script:OEMWarnings) {
            Write-Host "  ! $warning" -ForegroundColor DarkYellow
        }
    }
    Write-Host ""
}

function Show-CurrentStatus {
    $planName = Get-ActivePlanName
    $acMode = Get-CurrentBoostMode -PowerType "AC"
    $dcMode = Get-CurrentBoostMode -PowerType "DC"
    
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Active Power Plan: " -ForegroundColor White -NoNewline
    Write-Host "$planName" -ForegroundColor Green
    
    if (($null -ne $acMode) -and $script:BoostModes.ContainsKey([int]$acMode)) {
        $acName = $script:BoostModes[[int]$acMode].Name
        Write-Host "  AC (Plugged In):   " -ForegroundColor White -NoNewline
        Write-Host "$acName" -ForegroundColor Cyan
    } else {
        Write-Host "  AC (Plugged In):   " -ForegroundColor White -NoNewline
        Write-Host "Unknown" -ForegroundColor Red
    }
    
    if (($null -ne $dcMode) -and $script:BoostModes.ContainsKey([int]$dcMode)) {
        $dcName = $script:BoostModes[[int]$dcMode].Name
        Write-Host "  DC (Battery):      " -ForegroundColor White -NoNewline
        Write-Host "$dcName" -ForegroundColor Cyan
    } else {
        Write-Host "  DC (Battery):      " -ForegroundColor White -NoNewline
        Write-Host "Unknown" -ForegroundColor Red
    }
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Menu {
    Write-Host "  Select Turbo Boost Mode:" -ForegroundColor White
    
    # Detect current power source and get the active mode
    $powerSource = Get-CurrentPowerSource
    $activeMode = Get-CurrentBoostMode -PowerType $powerSource
    $sourceLabel = if ($powerSource -eq "AC") { "Plugged In" } else { "Battery" }
    
    Write-Host "  (Currently on: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$sourceLabel" -NoNewline -ForegroundColor Cyan
    Write-Host ")" -ForegroundColor DarkGray
    Write-Host ""
    
    foreach ($key in ($script:BoostModes.Keys | Sort-Object)) {
        $mode = $script:BoostModes[$key]
        if ($key -eq $activeMode) {
            $indicator = " <-- Active"
            $color = "Green"
        } else {
            $indicator = ""
            $color = "White"
        }
        
        Write-Host "    [$key] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($mode.Name)" -NoNewline -ForegroundColor $color
        Write-Host "$indicator" -ForegroundColor Green
        Write-Host "        $($mode.Description)" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    Write-Host "  ------------------------------------------------------------" -ForegroundColor DarkGray
    if ($script:SettingHidden) {
        Write-Host "    [R] Refresh   [P] Power Options   [V] Show in GUI   [Q] Quit" -ForegroundColor Magenta
        Write-Host "    (Setting is currently HIDDEN from Control Panel)" -ForegroundColor DarkYellow
    } else {
        Write-Host "    [R] Refresh   [P] Power Options   [V] Hide from GUI   [Q] Quit" -ForegroundColor Magenta
        Write-Host "    (Setting is currently VISIBLE in Control Panel)" -ForegroundColor DarkGreen
    }
    Write-Host ""
}

function Show-ApplyOptions {
    Write-Host ""
    Write-Host "  Apply to:" -ForegroundColor White
    Write-Host "    [1] Both AC and DC (Recommended)" -ForegroundColor Yellow
    Write-Host "    [2] AC only (Plugged In)" -ForegroundColor White
    Write-Host "    [3] DC only (Battery)" -ForegroundColor White
    Write-Host "    [C] Cancel" -ForegroundColor Red
    Write-Host ""
}

# Main loop
do {
    # Temporarily unhide to read values
    Ensure-SettingVisible
    
    Show-Header
    Show-CurrentStatus
    Show-Menu
    
    # Re-hide if user wanted it hidden
    if ($script:SettingHidden) {
        Hide-Setting
    }
    
    Write-Host "  Enter your choice: " -NoNewline -ForegroundColor White
    $choice = Read-Host
    
    switch ($choice.ToUpper()) {
        "Q" { 
            Write-Host ""
            Write-Host "  Goodbye!" -ForegroundColor Green
            Write-Host ""
            exit 
        }
        "R" { 
            continue 
        }
        "P" {
            Write-Host ""
            Write-Host "  Opening Power Options..." -ForegroundColor Yellow
            Start-Process "control.exe" -ArgumentList "powercfg.cpl,,3"
            continue
        }
        "V" {
            Write-Host ""
            if ($script:SettingHidden) {
                Write-Host "  Showing setting in Control Panel..." -ForegroundColor Yellow
                Ensure-SettingVisible
                $script:SettingHidden = $false
                Write-Host "  Done! Setting is now VISIBLE in Power Options GUI." -ForegroundColor Green
            } else {
                Write-Host "  Hiding setting from Control Panel..." -ForegroundColor Yellow
                Hide-Setting
                $script:SettingHidden = $true
                Write-Host "  Done! Setting is now HIDDEN from Power Options GUI." -ForegroundColor Green
                Write-Host "  (This script can still manage it)" -ForegroundColor DarkGray
            }
            Start-Sleep -Milliseconds 800
            continue
        }
        {[int]::TryParse($_, [ref]$null) -and $script:BoostModes.ContainsKey([int]$_)} {
            $modeValue = [int]$choice
            $modeName = $script:BoostModes[$modeValue].Name
            
            Write-Host ""
            Write-Host "  Selected: " -NoNewline -ForegroundColor White
            Write-Host "$modeName" -ForegroundColor Green
            
            Show-ApplyOptions
            Write-Host "  Enter your choice: " -NoNewline -ForegroundColor White
            $applyChoice = Read-Host
            
            $applyAC = $false
            $applyDC = $false
            
            switch ($applyChoice.ToUpper()) {
                "1" { $applyAC = $true; $applyDC = $true }
                "2" { $applyAC = $true }
                "3" { $applyDC = $true }
                "C" { continue }
                default { continue }
            }
            
            if ($applyAC -or $applyDC) {
                Write-Host ""
                Write-Host "  Applying changes..." -ForegroundColor Yellow
                
                $success = Set-BoostMode -ModeValue $modeValue -ApplyToAC $applyAC -ApplyToDC $applyDC
                
                if ($success) {
                    Write-Host "  [OK] Successfully applied: " -NoNewline -ForegroundColor Green
                    Write-Host "$modeName" -ForegroundColor Cyan
                    if ($applyAC -and $applyDC) {
                        Write-Host "       Applied to both AC and DC" -ForegroundColor DarkGray
                    } elseif ($applyAC) {
                        Write-Host "       Applied to AC only" -ForegroundColor DarkGray
                    } else {
                        Write-Host "       Applied to DC only" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "  [ERROR] Failed to apply settings" -ForegroundColor Red
                }
                
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
        }
        default {
            Write-Host ""
            Write-Host "  Invalid choice. Press any key to continue..." -ForegroundColor Red
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
    }
} while ($true)
