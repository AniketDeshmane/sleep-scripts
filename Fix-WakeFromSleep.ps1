#Requires -RunAsAdministrator
# ============================================================
#  Wake From Sleep - Interactive Diagnostic & Fix Tool
#  v2.0 -- Full Sleep & Wake Health Check
# ============================================================
#
# Checks and fixes:
#   [1] USB Selective Suspend        (blocks keyboard/mouse from waking PC)
#   [2] Keyboard & Mouse Wake        (per-device wake permission)
#   [3] USB Root Hub Wake            (hub must pass wake signals through)
#   [4] Hibernate                    (PC looks "shutdown" after sleeping too long)
#   [5] Unwanted Wake Sources        (PC wakes by itself -- timers, network, tasks)
#
# BIOS guidance included if software fixes are not enough.

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

# ────────────────────────────────────────────────────────────
# Helper Functions
# ────────────────────────────────────────────────────────────

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +==============================================================+" -ForegroundColor DarkCyan
    Write-Host "  |        Sleep & Wake -- Full Diagnostic & Fix Tool           |" -ForegroundColor Cyan
    Write-Host "  |        Keyboard / Mouse Wake + Hibernate + Deep Sleep       |" -ForegroundColor Cyan
    Write-Host "  |        v2.0 -- Windows 10 / 11                              |" -ForegroundColor DarkCyan
    Write-Host "  +==============================================================+" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Section($title) {
    Write-Host ""
    Write-Host "  +-------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  |  $title" -ForegroundColor Yellow
    Write-Host "  +-------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-OK($msg)      { Write-Host "    [OK]    $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    [WARN]  $msg" -ForegroundColor Yellow }
function Write-Issue($msg)   { Write-Host "    [FAIL]  $msg" -ForegroundColor Red }
function Write-Info($msg)    { Write-Host "    [INFO]  $msg" -ForegroundColor DarkGray }
function Write-Fixed($msg)   { Write-Host "    [FIXED] $msg" -ForegroundColor Cyan }
function Write-Skip($msg)    { Write-Host "    [SKIP]  $msg" -ForegroundColor DarkGray }

function Ask-YesNo($question) {
    Write-Host ""
    Write-Host "    >> $question" -ForegroundColor White
    Write-Host "       [Y] Fix it   [N] Skip   [Q] Quit" -ForegroundColor DarkGray
    Write-Host ""
    $choice = $null
    while ($choice -notin @('Y','N','Q')) {
        $raw = Read-Host "       Your choice"
        $choice = $raw.Trim().ToUpper()
        if ($choice -eq '') { $choice = 'N' }
    }
    if ($choice -eq 'Q') {
        Write-Host ""
        Write-Host "  Exiting. Goodbye!" -ForegroundColor DarkGray
        exit 0
    }
    return ($choice -eq 'Y')
}

function Wait-Enter {
    Write-Host ""
    Read-Host "    Press Enter to continue"
}

function Get-FriendlyName($instanceId) {
    $clean = $instanceId -replace "_\d+$", ""
    $dev = Get-PnpDevice -InstanceId $clean -ErrorAction SilentlyContinue
    if ($dev -and $dev.FriendlyName -and $dev.FriendlyName.Trim() -ne "") {
        return $dev.FriendlyName
    }
    if ($clean -match "VID_046D") { return "Logitech USB Receiver" }
    if ($clean -match "VID_1A2C") { return "USB Keyboard/Mouse (VID 1A2C)" }
    if ($clean -match "VID_045E") { return "Microsoft USB Device" }
    if ($clean -match "VID_04D9") { return "Holtek USB HID Device" }
    return "HID Device [$($clean -replace '.*\\','')]"
}

function Get-UsbSuspendAC {
    $raw = powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226
    $line = $raw | Select-String "Current AC Power Setting Index" | Select-Object -First 1
    if ($line -and "$line" -match "0x(\w+)") {
        return [Convert]::ToInt32($matches[1], 16)
    }
    return -1
}

function Get-WakeTimersAC {
    $raw = powercfg /query SCHEME_CURRENT SUB_SLEEP RTCWAKE
    $line = $raw | Select-String "Current AC Power Setting Index" | Select-Object -First 1
    if ($line -and "$line" -match "0x(\w+)") {
        return [Convert]::ToInt32($matches[1], 16)
    }
    return -1
}

function Get-HibernateEnabled {
    $states = powercfg /availablesleepstates
    $hibLine = $states | Select-String "Hibernate"
    # If "Hibernation has not been enabled" -> disabled
    if ("$hibLine" -match "not been enabled|not available") { return $false }
    return $true
}

# ────────────────────────────────────────────────────────────
# START
# ────────────────────────────────────────────────────────────

Write-Banner
Write-Host "  This tool checks and fixes 5 common sleep/wake issues on Windows." -ForegroundColor Gray
Write-Host "  For each issue found, you choose to fix it or skip it." -ForegroundColor Gray
Write-Host ""
Write-Host "  Checks:" -ForegroundColor White
Write-Host "    [1] USB Selective Suspend  -- keyboard/mouse cannot wake PC" -ForegroundColor DarkGray
Write-Host "    [2] Keyboard & Mouse Wake  -- per-device wake permission" -ForegroundColor DarkGray
Write-Host "    [3] USB Root Hub Wake      -- hub blocking wake signals" -ForegroundColor DarkGray
Write-Host "    [4] Hibernate              -- PC looks shutdown after sleep" -ForegroundColor DarkGray
Write-Host "    [5] Unwanted Wake Sources  -- PC waking up on its own" -ForegroundColor DarkGray
Write-Host ""
Wait-Enter

# ────────────────────────────────────────────────────────────
# DIAGNOSIS: Last wake source
# ────────────────────────────────────────────────────────────
Write-Banner
Write-Section "DIAGNOSIS -- What woke your PC last time?"

$wakeLog   = powercfg /lastwake
$wakeCount = "$($wakeLog | Select-String 'Wake History Count' | Select-Object -First 1)"
$wakeType  = "$($wakeLog | Select-String 'Type:' | Select-Object -First 1)"
$wakeDev   = "$($wakeLog | Select-String 'Instance Path:|Instance Name:|Name:' | Select-Object -First 1)"

if ($wakeCount -match "Count - 0") {
    Write-Info "No sleep/wake events recorded yet. Sleep the PC and wake it to populate this."
} elseif ($wakeType -match "Power Button") {
    Write-Issue "Last wake: POWER BUTTON -- keyboard/mouse are NOT waking the PC."
    Write-Info  "Check 1, 2, and 3 below will help fix this."
} elseif ($wakeType -match "Device") {
    Write-OK "Last wake was triggered by a DEVICE (keyboard/mouse)."
    if ($wakeDev.Trim()) { Write-OK "Device: $($wakeDev.Trim())" }
    Write-Info "Wake seems to be working. We will still verify all settings."
} else {
    Write-Info "Last wake type: $($wakeType.Trim())"
}

# Also show recent sleep history
Write-Host ""
Write-Host "  Recent sleep events (last 24 hours):" -ForegroundColor White
$sleepEvents = Get-WinEvent -FilterHashtable @{
    LogName='System'; Id=@(42,107); StartTime=(Get-Date).AddHours(-24)
} -ErrorAction SilentlyContinue | Sort-Object TimeCreated | Select-Object -Last 10
if ($sleepEvents) {
    foreach ($e in $sleepEvents) {
        $reason = if ($e.Id -eq 42) {
            ($e.Message | Select-String "Sleep Reason:(.*)").Matches.Groups[1].Value.Trim()
        } else { "WOKE UP" }
        $color = if ($e.Id -eq 107) { "Green" } else { "DarkGray" }
        Write-Host "    $($e.TimeCreated.ToString('HH:mm:ss'))  $(if($e.Id -eq 42){'-> SLEEP'}else{'<- WAKE '})  $reason" -ForegroundColor $color
    }
} else {
    Write-Info "No sleep/wake events in the last 24 hours."
}

Wait-Enter

# ────────────────────────────────────────────────────────────
# CHECK 1: USB Selective Suspend
# ────────────────────────────────────────────────────────────
Write-Banner
Write-Section "CHECK 1 of 5 -- USB Selective Suspend"

Write-Host "  WHAT IS THIS?" -ForegroundColor White
Write-Host "  USB Selective Suspend lets Windows cut power to USB ports during" -ForegroundColor DarkGray
Write-Host "  sleep to save battery. The side effect: keyboards and mice lose" -ForegroundColor DarkGray
Write-Host "  power and cannot send a wake signal to the PC." -ForegroundColor DarkGray
Write-Host ""

$suspendVal  = Get-UsbSuspendAC
$fix1Applied = $false

if ($suspendVal -eq 1) {
    Write-Issue "USB Selective Suspend is ENABLED"
    Write-Host ""
    Write-Host "    Current (AC power) : Enabled  -- blocks USB wake" -ForegroundColor Red
    Write-Host "    Recommended        : Disabled -- allows USB wake" -ForegroundColor Green

    if (Ask-YesNo "Disable USB Selective Suspend? (Recommended)") {
        powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
        powercfg /setactive SCHEME_CURRENT
        Write-Fixed "USB Selective Suspend disabled on AC and Battery power."
        $fix1Applied = $true
    } else {
        Write-Skip "Left as-is. USB wake may still be blocked."
    }

} elseif ($suspendVal -eq 0) {
    Write-OK "USB Selective Suspend is DISABLED -- USB devices can signal wake. Good!"
} else {
    Write-Warn "Could not read USB Selective Suspend state. Check Power Options manually."
}

Wait-Enter

# ────────────────────────────────────────────────────────────
# CHECK 2: Per-Device Wake Enable (HID keyboard/mouse)
# ────────────────────────────────────────────────────────────
Write-Banner
Write-Section "CHECK 2 of 5 -- Keyboard & Mouse Wake Permission"

Write-Host "  WHAT IS THIS?" -ForegroundColor White
Write-Host "  Each input device has a setting: 'Allow this device to wake the" -ForegroundColor DarkGray
Write-Host "  computer'. If OFF, Windows ignores that device while the PC sleeps." -ForegroundColor DarkGray
Write-Host ""

$allHid      = Get-WmiObject -Class MSPower_DeviceWakeEnable -Namespace root/WMI |
               Where-Object { $_.InstanceName -match "HID" }
$hidEnabled  = @($allHid | Where-Object { $_.Enable -eq $true })
$hidDisabled = @($allHid | Where-Object { $_.Enable -eq $false })

if ($hidEnabled.Count -gt 0) {
    Write-Host "  Devices ALLOWED to wake the PC:" -ForegroundColor White
    foreach ($d in $hidEnabled) {
        Write-OK (Get-FriendlyName $d.InstanceName)
    }
    Write-Host ""
}

$fix2Applied = $false

if ($hidDisabled.Count -eq 0) {
    Write-OK "All keyboard/mouse devices are allowed to wake the PC. Nothing to fix."
} else {
    Write-Host "  Devices NOT allowed to wake the PC:" -ForegroundColor White
    foreach ($d in $hidDisabled) {
        Write-Issue (Get-FriendlyName $d.InstanceName)
    }
    Write-Host ""

    if (Ask-YesNo "Enable wake permission for all devices listed above?") {
        $ok = 0; $bad = 0
        foreach ($d in $hidDisabled) {
            $name = Get-FriendlyName $d.InstanceName
            $d.Enable = $true
            try { $d.Put() | Out-Null; Write-Fixed "$name"; $ok++ }
            catch { Write-Warn "Could not enable: $name"; $bad++ }
        }
        Write-Host ""
        Write-Info "Result: $ok enabled, $bad could not be changed."
        if ($ok -gt 0) { $fix2Applied = $true }
    } else {
        Write-Skip "Device wake permissions left unchanged."
    }
}

Wait-Enter

# ────────────────────────────────────────────────────────────
# CHECK 3: USB Root Hub Wake Enable
# ────────────────────────────────────────────────────────────
Write-Banner
Write-Section "CHECK 3 of 5 -- USB Root Hub Wake Enable"

Write-Host "  WHAT IS THIS?" -ForegroundColor White
Write-Host "  USB Root Hubs are the internal controllers your USB ports connect to." -ForegroundColor DarkGray
Write-Host "  Even if a keyboard/mouse is allowed to wake the PC, the hub it is" -ForegroundColor DarkGray
Write-Host "  plugged into must also be allowed to pass the wake signal through." -ForegroundColor DarkGray
Write-Host ""

$allHubs     = @(Get-PnpDevice | Where-Object { $_.FriendlyName -match "USB Root Hub|Generic USB Hub" })
$hubsOk      = @()
$hubsBad     = @()
$fix3Applied = $false

foreach ($hub in $allHubs) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($hub.InstanceId)\Device Parameters"
    $wakeVal = $null
    if (Test-Path $path) {
        $prop = Get-ItemProperty -Path $path -Name "WakeEnabled" -ErrorAction SilentlyContinue
        $wakeVal = $prop.WakeEnabled
    }
    if ($wakeVal -eq 1) { $hubsOk += $hub } else { $hubsBad += $hub }
}

if ($hubsOk.Count -gt 0) {
    Write-Host "  Hubs ALLOWED to pass wake signals:" -ForegroundColor White
    foreach ($h in $hubsOk) { Write-OK "$($h.FriendlyName)   [$($h.InstanceId)]" }
    Write-Host ""
}

if ($hubsBad.Count -eq 0) {
    Write-OK "All USB hubs are configured correctly. Nothing to fix."
} else {
    Write-Host "  Hubs that may be BLOCKING wake signals:" -ForegroundColor White
    foreach ($h in $hubsBad) { Write-Issue "$($h.FriendlyName)   [$($h.InstanceId)]" }
    Write-Host ""

    if (Ask-YesNo "Enable wake on all listed USB hubs?") {
        $ok = 0; $bad = 0
        foreach ($h in $hubsBad) {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($h.InstanceId)\Device Parameters"
            try {
                if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                Set-ItemProperty -Path $path -Name "WakeEnabled" -Value 1 -Type DWord -Force
                Write-Fixed "$($h.FriendlyName)"
                $ok++
            } catch {
                Write-Warn "Could not update: $($h.FriendlyName) -- $($_.Exception.Message)"
                $bad++
            }
        }
        Write-Info "Result: $ok hubs fixed, $bad could not be changed."
        if ($ok -gt 0) { $fix3Applied = $true }
    } else {
        Write-Skip "USB hub settings left unchanged."
    }
}

Wait-Enter

# ────────────────────────────────────────────────────────────
# CHECK 4: Hibernate
# ────────────────────────────────────────────────────────────
Write-Banner
Write-Section "CHECK 4 of 5 -- Hibernate (PC looks Shutdown after Sleep)"

Write-Host "  WHAT IS THIS?" -ForegroundColor White
Write-Host "  When Hibernate is ON, Windows automatically converts Sleep into" -ForegroundColor DarkGray
Write-Host "  Hibernate after a set time (e.g. 3 hours). Hibernate saves RAM" -ForegroundColor DarkGray
Write-Host "  to disk and fully powers off -- making the PC look like it was" -ForegroundColor DarkGray
Write-Host "  shut down. This also disables Fast Startup when turned off." -ForegroundColor DarkGray
Write-Host ""

$hibEnabled  = Get-HibernateEnabled
$fix4Applied = $false

# Check hibernate-after timeout
$hibRaw  = powercfg /query SCHEME_CURRENT SUB_SLEEP HIBERNATEIDLE
$hibLine = $hibRaw | Select-String "Current AC Power Setting Index" | Select-Object -First 1
$hibSecs = -1
if ($hibLine -and "$hibLine" -match "0x(\w+)") {
    $hibSecs = [Convert]::ToInt32($matches[1], 16)
}

if (-not $hibEnabled) {
    Write-OK "Hibernate is DISABLED -- PC will stay in Sleep mode. Good!"
    Write-Info "Fast Startup is also disabled (slightly slower cold boot, but more stable sleep)."
} else {
    Write-Issue "Hibernate is ENABLED"
    Write-Host ""
    if ($hibSecs -gt 0) {
        $hibMins = [math]::Round($hibSecs / 60)
        $hibHrs  = [math]::Round($hibMins / 60, 1)
        Write-Host "    Hibernate triggers after : $hibSecs seconds ($hibMins min / $hibHrs hrs) of sleep" -ForegroundColor Red
        Write-Host "    Effect : PC appears OFF after sleeping $hibHrs hours" -ForegroundColor Red
    } elseif ($hibSecs -eq 0) {
        Write-Host "    Hibernate-after timeout : Never (but hidden Fixed Timeout may still apply)" -ForegroundColor Yellow
        Write-Info "  Windows has a hidden 'Hibernate from Sleep - Fixed Timeout' that"
        Write-Info "  can trigger even when the above shows Never. Disabling hibernate"
        Write-Info "  completely is the only reliable fix."
    }
    Write-Host ""
    Write-Host "    Disabling hibernate will also:" -ForegroundColor DarkGray
    Write-Host "      - Remove the Hibernate option from the Start menu" -ForegroundColor DarkGray
    Write-Host "      - Disable Fast Startup (boot is ~5-10 sec slower)" -ForegroundColor DarkGray
    Write-Host "      - Delete hiberfil.sys (frees disk space)" -ForegroundColor DarkGray

    if (Ask-YesNo "Disable Hibernate completely? (Recommended for stable sleep)") {
        powercfg /hibernate off
        Write-Fixed "Hibernate fully disabled. PC will now stay in Sleep mode."
        $fix4Applied = $true
    } else {
        Write-Skip "Hibernate left enabled."
        if ($hibSecs -gt 0) {
            Write-Info "Tip: You can increase the timeout in Power Options -> Advanced -> Sleep -> Hibernate after."
        }
    }
}

Wait-Enter

# ────────────────────────────────────────────────────────────
# CHECK 5: Unwanted Wake Sources (PC waking by itself)
# ────────────────────────────────────────────────────────────
Write-Banner
Write-Section "CHECK 5 of 5 -- Unwanted Wake Sources (PC waking by itself)"

Write-Host "  WHAT IS THIS?" -ForegroundColor White
Write-Host "  Several Windows features can wake your PC from sleep without you" -ForegroundColor DarkGray
Write-Host "  touching it: scheduled tasks (e.g. Windows Update), network adapters" -ForegroundColor DarkGray
Write-Host "  (Wake on LAN), Thunderbolt controllers, and wake timers." -ForegroundColor DarkGray
Write-Host ""

$fix5Applied   = $false
$anyWakeIssues = $false

# --- 5a: Allow Wake Timers ---
Write-Host "  [5a] Wake Timers (Allow scheduled tasks/apps to wake PC):" -ForegroundColor White
$rtcVal = Get-WakeTimersAC
if ($rtcVal -eq 0) {
    Write-OK "Wake Timers are DISABLED -- nothing can schedule a wake."
} elseif ($rtcVal -eq 1) {
    Write-Issue "Wake Timers are ENABLED -- any app or task can wake your PC on AC power."
    $anyWakeIssues = $true
} elseif ($rtcVal -eq 2) {
    Write-Warn "Wake Timers set to 'Important Wake Timers Only' -- Windows Update can still wake PC."
    $anyWakeIssues = $true
} else {
    Write-Warn "Could not read Wake Timers setting."
}

Write-Host ""

# --- 5b: Thunderbolt Controller ---
Write-Host "  [5b] Thunderbolt Controller (can wake PC via connected devices):" -ForegroundColor White
$tbWmi = Get-WmiObject -Class MSPower_DeviceWakeEnable -Namespace root/WMI |
         Where-Object { $_.InstanceName -match "9A1F" } | Select-Object -First 1
$tbDev = Get-PnpDevice | Where-Object { $_.FriendlyName -match "Thunderbolt" -and $_.FriendlyName -match "Controller" } | Select-Object -First 1
$tbName = if ($tbDev) { $tbDev.FriendlyName } else { "Thunderbolt Controller" }

if ($tbWmi -and $tbWmi.Enable) {
    Write-Issue "$tbName -- wake is ENABLED (can be triggered by docking/undocking)"
    $anyWakeIssues = $true
} elseif ($tbWmi) {
    Write-OK "$tbName -- wake is DISABLED. Good!"
} else {
    Write-Info "No Thunderbolt controller found in wake list."
}

Write-Host ""

# --- 5c: Scheduled Tasks with WakeToRun ---
Write-Host "  [5c] Scheduled Tasks that can wake the PC:" -ForegroundColor White
$wakeTasks = @(Get-ScheduledTask | Where-Object { $_.Settings.WakeToRun -eq $true })
if ($wakeTasks.Count -eq 0) {
    Write-OK "No scheduled tasks are set to wake the PC. Good!"
} else {
    foreach ($t in $wakeTasks) {
        Write-Issue "Task: $($t.TaskName)  [$($t.TaskPath)]"
    }
    $anyWakeIssues = $true
}

Write-Host ""

# --- 5d: Network Adapter Wake on LAN ---
Write-Host "  [5d] Network Adapters -- Wake on LAN / Magic Packet:" -ForegroundColor White
$adapters = Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue |
            Where-Object { $_.WakeOnMagicPacket -eq "Enabled" -or $_.WakeOnPattern -eq "Enabled" }
if ($adapters) {
    foreach ($a in $adapters) {
        Write-Issue "Adapter: $($a.Name) -- WakeOnMagicPacket=$($a.WakeOnMagicPacket), WakeOnPattern=$($a.WakeOnPattern)"
    }
    $anyWakeIssues = $true
} else {
    Write-OK "No network adapters have Wake on LAN enabled. Good!"
}

Write-Host ""

# --- Offer to fix all ---
if (-not $anyWakeIssues) {
    Write-OK "No unwanted wake sources found. Your PC should sleep undisturbed."
} else {
    if (Ask-YesNo "Fix all unwanted wake sources listed above?") {

        # Fix wake timers
        if ($rtcVal -ne 0) {
            powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 0
            powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 0
            powercfg /setactive SCHEME_CURRENT
            Write-Fixed "Wake Timers disabled on AC and Battery."
        }

        # Fix Thunderbolt
        if ($tbWmi -and $tbWmi.Enable) {
            $tbWmi.Enable = $false
            try {
                $tbWmi.Put() | Out-Null
                Write-Fixed "$tbName -- wake disabled."
            } catch {
                # Fallback: registry
                $tbId = if ($tbDev) { $tbDev.InstanceId } else { "PCI\VEN_8086&DEV_9A1F&SUBSYS_22D817AA&REV_05\3&11583659&0&6A" }
                $tbReg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$tbId\Device Parameters"
                if (Test-Path $tbReg) {
                    Set-ItemProperty -Path $tbReg -Name "WakeEnabled" -Value 0 -Type DWord -Force
                    Write-Fixed "$tbName -- wake disabled via registry."
                } else {
                    Write-Warn "Could not disable Thunderbolt wake."
                }
            }
        }

        # Fix scheduled tasks
        $tasksFixed = 0
        foreach ($t in $wakeTasks) {
            try {
                $t.Settings.WakeToRun = $false
                Set-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
                Write-Fixed "Task disabled: $($t.TaskName)"
                $tasksFixed++
            } catch {
                Write-Warn "Could not disable task: $($t.TaskName)"
            }
        }

        # Fix Wake on LAN
        foreach ($a in $adapters) {
            try {
                Set-NetAdapterPowerManagement -Name $a.Name -WakeOnMagicPacket Disabled -WakeOnPattern Disabled -ErrorAction Stop
                Write-Fixed "Wake on LAN disabled for: $($a.Name)"
            } catch {
                Write-Warn "Could not disable WoL for: $($a.Name)"
            }
        }

        $fix5Applied = $true
    } else {
        Write-Skip "Unwanted wake sources left unchanged."
    }
}

Wait-Enter

# ────────────────────────────────────────────────────────────
# SUMMARY
# ────────────────────────────────────────────────────────────
Write-Banner
Write-Section "SUMMARY -- Final Status & Changes Made"

$suspendFinal = Get-UsbSuspendAC
$rtcFinal     = Get-WakeTimersAC
$hibFinal     = Get-HibernateEnabled
$armedNow     = powercfg /devicequery wake_armed

Write-Host "  CURRENT SETTINGS:" -ForegroundColor White
Write-Host ""

# USB Selective Suspend
if ($suspendFinal -eq 0) {
    Write-OK "USB Selective Suspend    -->  Disabled  (correct)"
} else {
    Write-Issue "USB Selective Suspend    -->  Still ENABLED (may block keyboard/mouse wake)"
}

# Wake Timers
if ($rtcFinal -eq 0) {
    Write-OK "Wake Timers              -->  Disabled  (PC won't wake by itself)"
} elseif ($rtcFinal -eq 1) {
    Write-Issue "Wake Timers              -->  Still ENABLED (apps/tasks can wake PC)"
} else {
    Write-Warn "Wake Timers              -->  Important Only (Windows Update can still wake)"
}

# Hibernate
if (-not $hibFinal) {
    Write-OK "Hibernate                -->  Disabled  (PC stays in Sleep, never powers off)"
} else {
    Write-Issue "Hibernate                -->  Still ENABLED (PC may power off after extended sleep)"
}

# Armed devices
Write-Host ""
Write-Host "  Devices armed to wake your PC:" -ForegroundColor White
$deviceLines = @($armedNow | Where-Object { $_ -match "\S" })
if ($deviceLines.Count -gt 0) {
    foreach ($line in $deviceLines) { Write-OK $line.Trim() }
} else {
    Write-Issue "No devices are armed -- keyboard/mouse will NOT wake the PC!"
}

# Changes summary
Write-Host ""
Write-Host "  CHANGES MADE THIS SESSION:" -ForegroundColor White
$anyFix = $fix1Applied -or $fix2Applied -or $fix3Applied -or $fix4Applied -or $fix5Applied
if ($fix1Applied) { Write-Fixed "USB Selective Suspend disabled" }
if ($fix2Applied) { Write-Fixed "Keyboard/Mouse device wake permissions enabled" }
if ($fix3Applied) { Write-Fixed "USB Root Hub(s) wake enabled" }
if ($fix4Applied) { Write-Fixed "Hibernate disabled (PC stays in Sleep)" }
if ($fix5Applied) { Write-Fixed "Unwanted wake sources disabled (timers, tasks, network)" }
if (-not $anyFix)  { Write-Info  "No changes were made this session." }

# ────────────────────────────────────────────────────────────
# BIOS GUIDANCE
# ────────────────────────────────────────────────────────────
Write-Host ""
Write-Section "BIOS / UEFI -- If Software Fixes Did Not Help"

Write-Host "  Some PCs block USB wake at the hardware/firmware level." -ForegroundColor DarkGray
Write-Host "  Windows cannot override this -- you must enable it in BIOS/UEFI." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  How to access BIOS/UEFI:" -ForegroundColor White
Write-Host "    1. Restart your PC" -ForegroundColor Gray
Write-Host "    2. Tap Del / F2 / F10 / Esc repeatedly during the boot logo" -ForegroundColor Gray
Write-Host "       (key varies by brand -- check your laptop/motherboard manual)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  What to enable in BIOS:" -ForegroundColor White
Write-Host "    Location : Power -> Advanced -> ACPI Settings" -ForegroundColor Gray
Write-Host "    Look for :" -ForegroundColor Gray
Write-Host "      * USB Wake Support" -ForegroundColor Cyan
Write-Host "      * USB Keyboard Wake" -ForegroundColor Cyan
Write-Host "      * USB Mouse Wake" -ForegroundColor Cyan
Write-Host "      * Power On By USB" -ForegroundColor Cyan
Write-Host "      * Wake on USB" -ForegroundColor Cyan
Write-Host "    Set to   : Enabled" -ForegroundColor Green
Write-Host ""
Write-Host "  TIP: Plug keyboard/mouse directly into motherboard USB ports," -ForegroundColor DarkGray
Write-Host "       not through a USB hub or docking station." -ForegroundColor DarkGray

# ────────────────────────────────────────────────────────────
# CLOSING
# ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
if ($anyFix) {
    Write-Host "  Changes were applied. No restart needed for most fixes." -ForegroundColor Cyan
    Write-Host "  To test: Start -> Power -> Sleep, then press a key or move mouse." -ForegroundColor Cyan
} else {
    Write-Host "  No changes were applied this session." -ForegroundColor Yellow
    Write-Host "  If issues persist, check BIOS settings described above." -ForegroundColor Yellow
}
Write-Host "  ----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host ""
Read-Host "  Press Enter to exit"
