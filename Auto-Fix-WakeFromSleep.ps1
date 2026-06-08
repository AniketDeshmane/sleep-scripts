#Requires -RunAsAdministrator
# ============================================================
#  Sleep & Wake -- Auto Fix Script (Non-Interactive)
#  Tailored for this specific machine
#  Just double-click and it fixes everything automatically.
# ============================================================

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

$pass = 0
$fail = 0

function Write-Header($text) {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step($n, $desc) {
    Write-Host "  [$n] $desc" -ForegroundColor White -NoNewline
    Write-Host (" " * [math]::Max(1, 52 - $desc.Length)) -NoNewline
}

function Write-Done  { Write-Host "DONE" -ForegroundColor Green;  $script:pass++ }
function Write-Fail($reason) { Write-Host "FAIL  ($reason)" -ForegroundColor Red; $script:fail++ }
function Write-Already { Write-Host "Already OK" -ForegroundColor DarkGreen; $script:pass++ }

# ────────────────────────────────────────────────────────────

Write-Header "Sleep & Wake Auto-Fix  |  Running all fixes..."

# ── FIX 1: USB Selective Suspend ─────────────────────────────
Write-Step 1 "Disable USB Selective Suspend (AC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    Write-Done
} catch { Write-Fail $_.Exception.Message }

Write-Step 2 "Disable USB Selective Suspend (Battery)"
try {
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setactive SCHEME_CURRENT
    Write-Done
} catch { Write-Fail $_.Exception.Message }

# ── FIX 2: Enable Wake for All HID Keyboard & Mouse Devices ──
Write-Step 3 "Enable wake for all HID keyboard/mouse"
$hidDevs  = Get-WmiObject -Class MSPower_DeviceWakeEnable -Namespace root/WMI |
            Where-Object { $_.InstanceName -match "HID" -and $_.Enable -eq $false }
$hidFixed = 0
foreach ($d in $hidDevs) {
    $d.Enable = $true
    try { $d.Put() | Out-Null; $hidFixed++ } catch {}
}
if ($hidDevs.Count -eq 0) { Write-Already }
else { Write-Done; Write-Host "          --> Enabled $hidFixed device(s)" -ForegroundColor DarkGray }

# ── FIX 3: USB Root Hub Wake (Registry) ──────────────────────
Write-Step 4 "Enable wake on USB Root Hubs (registry)"
$hubs    = @(Get-PnpDevice | Where-Object { $_.FriendlyName -match "USB Root Hub|Generic USB Hub" })
$hubOk   = 0
$hubFail = 0
foreach ($h in $hubs) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($h.InstanceId)\Device Parameters"
    try {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "WakeEnabled" -Value 1 -Type DWord -Force
        $hubOk++
    } catch { $hubFail++ }
}
if ($hubFail -gt 0) { Write-Fail "$hubFail hub(s) failed" }
else { Write-Done; Write-Host "          --> Set on $hubOk hub(s)" -ForegroundColor DarkGray }

# ── FIX 4: Disable Hibernate Completely ──────────────────────
Write-Step 5 "Disable Hibernate (powercfg /hibernate off)"
powercfg /hibernate off 2>$null
$states  = powercfg /availablesleepstates
$hibLine = "$($states | Select-String 'Hibernate' | Select-Object -First 1)"
if ($hibLine -match "not been enabled|not available") { Write-Done }
else { Write-Fail "Still showing enabled -- try running this script again" }

# ── FIX 5: Disable Wake Timers ───────────────────────────────
Write-Step 6 "Disable Wake Timers (AC)"
try {
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 0
    Write-Done
} catch { Write-Fail $_.Exception.Message }

Write-Step 7 "Disable Wake Timers (Battery)"
try {
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 0
    powercfg /setactive SCHEME_CURRENT
    Write-Done
} catch { Write-Fail $_.Exception.Message }

# ── FIX 6: Disable Thunderbolt Controller Wake ───────────────
Write-Step 8 "Disable Thunderbolt Controller wake"
$tb = Get-WmiObject -Class MSPower_DeviceWakeEnable -Namespace root/WMI |
      Where-Object { $_.InstanceName -match "9A1F" } | Select-Object -First 1
if (-not $tb) {
    Write-Already
} elseif ($tb.Enable -eq $false) {
    Write-Already
} else {
    $tb.Enable = $false
    $tbFixed = $false
    try { $tb.Put() | Out-Null; $tbFixed = $true } catch {}
    if (-not $tbFixed) {
        # Fallback via registry
        $tbDev = Get-PnpDevice | Where-Object { $_.FriendlyName -match "Thunderbolt.*Controller" } | Select-Object -First 1
        if ($tbDev) {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($tbDev.InstanceId)\Device Parameters"
            try {
                Set-ItemProperty -Path $regPath -Name "WakeEnabled" -Value 0 -Type DWord -Force
                $tbFixed = $true
            } catch {}
        }
    }
    if ($tbFixed) { Write-Done } else { Write-Fail "Could not disable via WMI or registry" }
}

# ── FIX 7: Disable WakeToRun on Scheduled Tasks ──────────────
Write-Step 9 "Disable WakeToRun on scheduled tasks"
$tasks   = @(Get-ScheduledTask | Where-Object { $_.Settings.WakeToRun -eq $true })
$taskOk  = 0
$taskFail= 0
foreach ($t in $tasks) {
    try {
        $t.Settings.WakeToRun = $false
        Set-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
        $taskOk++
    } catch { $taskFail++ }
}
if ($tasks.Count -eq 0) { Write-Already }
elseif ($taskFail -gt 0) { Write-Fail "$taskFail task(s) could not be updated" }
else { Write-Done; Write-Host "          --> Disabled $taskOk task(s)" -ForegroundColor DarkGray }

# ── FIX 8: Disable Wake on LAN ───────────────────────────────
Write-Step 10 "Disable Wake on LAN on network adapters"
$wolAdapters = @(Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue |
                 Where-Object { $_.WakeOnMagicPacket -eq "Enabled" -or $_.WakeOnPattern -eq "Enabled" })
$wolOk   = 0
$wolFail = 0
foreach ($a in $wolAdapters) {
    try {
        Set-NetAdapterPowerManagement -Name $a.Name -WakeOnMagicPacket Disabled -WakeOnPattern Disabled -ErrorAction Stop
        $wolOk++
    } catch { $wolFail++ }
}
if ($wolAdapters.Count -eq 0) { Write-Already }
elseif ($wolFail -gt 0) { Write-Fail "$wolFail adapter(s) failed" }
else { Write-Done; Write-Host "          --> Disabled on $wolOk adapter(s)" -ForegroundColor DarkGray }

# ────────────────────────────────────────────────────────────
# VERIFICATION
# ────────────────────────────────────────────────────────────
Write-Header "Verifying all settings..."

$vPass = 0; $vFail = 0; $vWarn = 0

function Check($label, $ok, $warn=$false, $note="") {
    $tag   = if ($ok) { if ($warn) {"WARN"} else {"OK"} } else {"FAIL"}
    $color = if ($ok) { if ($warn) {"Yellow"} else {"Green"} } else {"Red"}
    $pad   = " " * [math]::Max(1, 50 - $label.Length)
    Write-Host "  [$tag]  $label$pad" -ForegroundColor $color -NoNewline
    if ($note) { Write-Host $note -ForegroundColor DarkGray } else { Write-Host "" }
    if ($ok -and -not $warn) { $script:vPass++ } elseif ($ok -and $warn) { $script:vWarn++ } else { $script:vFail++ }
}

# 1. USB Selective Suspend
$r  = powercfg /query SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226
$ac = if (($r|Select-String "Current AC") -match "0x(\w+)") {[Convert]::ToInt32($matches[1],16)} else {-1}
$dc = if (($r|Select-String "Current DC") -match "0x(\w+)") {[Convert]::ToInt32($matches[1],16)} else {-1}
Check "USB Selective Suspend (AC)"      ($ac -eq 0)
Check "USB Selective Suspend (Battery)" ($dc -eq 0)

# 2. Armed devices
$armed = @(powercfg /devicequery wake_armed | Where-Object { $_ -match "\S" })
Check "Keyboard/Mouse armed to wake PC  [$($armed.Count) devices]" ($armed.Count -gt 0)

# 3. USB Root Hubs
$hubs = @(Get-PnpDevice | Where-Object { $_.FriendlyName -match "USB Root Hub|Generic USB Hub" })
$hubsOk = ($hubs | Where-Object {
    $p = "HKLM:\SYSTEM\CurrentControlSet\Enum\$($_.InstanceId)\Device Parameters"
    (Test-Path $p) -and ((Get-ItemProperty $p -Name WakeEnabled -ErrorAction SilentlyContinue).WakeEnabled -eq 1)
}).Count
Check "USB Root Hubs with wake enabled  [$hubsOk of $($hubs.Count)]" ($hubsOk -eq $hubs.Count)

# 4. Hibernate
$states  = powercfg /availablesleepstates
$hibLine = "$($states | Select-String 'Hibernate' | Select-Object -First 1)"
$hibOff  = $hibLine -match "not been enabled|not available"
Check "Hibernate disabled" $hibOff

# 5. Wake Timers
$rtc   = powercfg /query SCHEME_CURRENT SUB_SLEEP RTCWAKE
$rtcAC = if (($rtc|Select-String "Current AC") -match "0x(\w+)") {[Convert]::ToInt32($matches[1],16)} else {-1}
$rtcDC = if (($rtc|Select-String "Current DC") -match "0x(\w+)") {[Convert]::ToInt32($matches[1],16)} else {-1}
Check "Wake Timers disabled (AC)"      ($rtcAC -eq 0)
Check "Wake Timers disabled (Battery)" ($rtcDC -eq 0)

# 6. Thunderbolt
$tb = Get-WmiObject -Class MSPower_DeviceWakeEnable -Namespace root/WMI |
      Where-Object { $_.InstanceName -match "9A1F" } | Select-Object -First 1
Check "Thunderbolt Controller wake off" (-not $tb -or $tb.Enable -eq $false)

# 7. Scheduled Tasks
$wt = @(Get-ScheduledTask | Where-Object { $_.Settings.WakeToRun -eq $true })
Check "No scheduled tasks wake PC      [$($wt.Count) remaining]" ($wt.Count -eq 0)

# 8. Wake on LAN
$wol = @(Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue |
         Where-Object { $_.WakeOnMagicPacket -eq "Enabled" -or $_.WakeOnPattern -eq "Enabled" })
Check "Wake on LAN disabled            [$($wol.Count) adapters with WoL]" ($wol.Count -eq 0)

# ────────────────────────────────────────────────────────────
# RESULT
# ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  ============================================================" -ForegroundColor DarkCyan
$resultColor = if ($vFail -gt 0) {"Red"} elseif ($vWarn -gt 0) {"Yellow"} else {"Green"}
Write-Host "  RESULT:  $vPass passed   $vWarn warnings   $vFail failed" -ForegroundColor $resultColor
Write-Host "  ============================================================" -ForegroundColor DarkCyan
Write-Host ""
if ($vFail -eq 0) {
    Write-Host "  All done! Your PC is fully configured." -ForegroundColor Green
    Write-Host "  Sleep/wake should work perfectly now." -ForegroundColor Green
} else {
    Write-Host "  $vFail check(s) failed. Run this script again as Administrator." -ForegroundColor Red
}
Write-Host ""
Read-Host "  Press Enter to close"
