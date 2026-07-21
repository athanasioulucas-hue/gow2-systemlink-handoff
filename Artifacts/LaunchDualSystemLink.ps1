# LaunchDualSystemLink.ps1
# Automated dual-instance launcher with 4-second position lock and native INI auto-startup

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
}

$HostDir   = "C:\GoW2Hollow\Gears of War 2 - Hollow"
$ClientDir = "C:\GoW2Hollow\Gears of War 2 - Hollow - Client2"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " HOLLOW NATIVE AUTO-START DUAL LAUNCHER " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Monitor Bounds:
# Monitor 1 (Main Screen / Right) : X = 0, Y = 0 (Run Search / Client)
# Monitor 2 (Top Screen / Above)  : X = -1074, Y = -1080 (Run Party / Host)

$monHost   = [System.Drawing.Rectangle]::FromLTRB(-1074, -1080, 846, -40)  # Monitor 2 (Top)
$monClient = [System.Drawing.Rectangle]::FromLTRB(0, 0, 1920, 1040)       # Monitor 1 (Main/Right)

Write-Host "Host Directory   : $HostDir (AutoStartMode=Host)" -ForegroundColor Gray
Write-Host "Client Directory : $ClientDir (AutoStartMode=Client)" -ForegroundColor Gray
Write-Host "Target Host   (Monitor 2 / Top) : X=-1074, Y=-1080" -ForegroundColor Yellow
Write-Host "Target Client (Monitor 1 / Main): X=0, Y=0" -ForegroundColor Yellow

# Stop hanging instances
Stop-Process -Name "GoW2Hollow*" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

function Start-GameInstance {
    param(
        [string]$Label,
        [string]$WorkingDir
    )

    Write-Host "`n[+] Starting $Label from '$WorkingDir'..." -ForegroundColor Green
    $launcher = Join-Path $WorkingDir "GoW2Hollow_Launcher.exe"
    $initialPids = (Get-Process GoW2Hollow -ErrorAction SilentlyContinue).Id

    $pLauncher = Start-Process -FilePath $launcher -WorkingDirectory $WorkingDir -PassThru
    Start-Sleep -Seconds 2

    # Send Enter to launcher UI
    $wshell = New-Object -ComObject WScript.Shell
    $wshell.AppActivate($pLauncher.Id) | Out-Null
    Start-Sleep -Milliseconds 300
    $wshell.SendKeys("{ENTER}")
    $wshell.SendKeys(" ")

    # Wait for game process
    $gameProc = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $currentProcs = Get-Process GoW2Hollow -ErrorAction SilentlyContinue
        foreach ($cp in $currentProcs) {
            if ($initialPids -notcontains $cp.Id) {
                $gameProc = $cp
                break
            }
        }
        if ($gameProc) { break }
    }

    if ($gameProc) {
        Write-Host "    $Label PID: $($gameProc.Id)" -ForegroundColor Cyan
        return $gameProc
    }
    return $null
}

# 1. Launch Instance 1 (Host)
$hProc = Start-GameInstance -Label "Instance 1 (Host / Party)" -WorkingDir $HostDir
Start-Sleep -Seconds 2

# 2. Launch Instance 2 (Client)
$cProc = Start-GameInstance -Label "Instance 2 (Client / Search)" -WorkingDir $ClientDir

# 3. Active 4-second position watcher loop (as requested)
Write-Host "`n[+] Locking window positions for 4 seconds..." -ForegroundColor Cyan
for ($sec = 1; $sec -le 4; $sec++) {
    Start-Sleep -Seconds 1
    if ($hProc -and $hProc.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32]::MoveWindow($hProc.MainWindowHandle, $monHost.X, $monHost.Y, $monHost.Width, $monHost.Height, $true) | Out-Null
    }
    if ($cProc -and $cProc.MainWindowHandle -ne [IntPtr]::Zero) {
        [Win32]::MoveWindow($cProc.MainWindowHandle, $monClient.X, $monClient.Y, $monClient.Width, $monClient.Height, $true) | Out-Null
    }
}

$hPid = if ($hProc) { $hProc.Id } else { "N/A" }
$cPid = if ($cProc) { $cProc.Id } else { "N/A" }

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " NATIVE AUTO-START DUAL LAUNCH COMPLETE!" -ForegroundColor Green
Write-Host " Instance 1 Host   (PID $hPid)   -> Monitor 2 (Top Screen - Hosting Party)" -ForegroundColor Yellow
Write-Host " Instance 2 Client (PID $cPid) -> Monitor 1 (Main / Right - Searching)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
