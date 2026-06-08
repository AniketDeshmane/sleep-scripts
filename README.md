# 💤 Sleep & Wake Fix Scripts for Windows

Fix keyboard/mouse not waking PC from sleep, unexpected wake-ups, and auto-hibernate issues on Windows 10/11.

---

## ⚡ Run in One Command (Fastest Way)

Open **PowerShell as Administrator** and paste this:

```powershell
irm https://raw.githubusercontent.com/AniketDeshmane/sleep-scripts/main/Auto-Fix-WakeFromSleep.ps1 | iex
```

> Fixes all 10 settings automatically. No download needed. Expected result: **10 passed, 0 failed**.

---

## 🚀 Quick Start — Just Run and Fix Everything

> **Download** → Right-click `.cmd` file → **Run as Administrator**

### Option 1 — Auto Fix (No Prompts) ⚡
Fixes all known issues automatically. Just run and done.

```
Run Me - Auto Fix (No Prompts).cmd
```

**What it fixes:**
| # | Fix |
|---|---|
| 1 | USB Selective Suspend disabled (AC + Battery) |
| 2 | Keyboard & Mouse wake permissions enabled |
| 3 | USB Root Hub wake enabled (registry) |
| 4 | Hibernate disabled (`powercfg /hibernate off`) |
| 5 | Wake Timers disabled (AC + Battery) |
| 6 | Thunderbolt Controller wake disabled |
| 7 | Scheduled tasks wake disabled (Windows Update etc.) |
| 8 | Wake on LAN disabled |

Then runs a **full verification** showing pass/fail for every setting.

---

### Option 2 — Interactive Tool 🔧
Step-by-step guide. Explains each issue, asks Y/N before applying each fix.

```
Run Me - Wake Fix Tool.cmd
```

**Checks covered (v2.0):**
- ✅ Diagnosis — shows what woke your PC last time + 24hr sleep history
- ✅ Check 1 — USB Selective Suspend
- ✅ Check 2 — Keyboard & Mouse wake permission (by full device name)
- ✅ Check 3 — USB Root Hub wake
- ✅ Check 4 — Hibernate (detects timeout, offers to disable)
- ✅ Check 5 — Unwanted wake sources (timers, Thunderbolt, tasks, WoL)
- ✅ BIOS/UEFI guidance if software fixes aren't enough

---

## 📋 Problems These Scripts Solve

| Symptom | Cause | Fixed by |
|---|---|---|
| PC only wakes with power button | USB Selective Suspend ON, or device wake disabled | Auto-Fix or Interactive |
| PC wakes up by itself at night | Wake timers, Windows Update tasks, Thunderbolt | Auto-Fix or Interactive |
| PC looks "shut down" after sleeping | Hibernate triggered after 3 hours | Auto-Fix or Interactive |
| Keyboard/mouse not waking PC | HID device wake permission OFF | Auto-Fix or Interactive |

---

## 📁 Files

| File | Description |
|---|---|
| `Auto-Fix-WakeFromSleep.ps1` | Non-interactive fix script (called by the `.cmd`) |
| `Fix-WakeFromSleep.ps1` | Interactive diagnostic + fix script v2.0 |
| `Run Me - Auto Fix (No Prompts).cmd` | Double-click launcher for auto fix |
| `Run Me - Wake Fix Tool.cmd` | Double-click launcher for interactive tool |

---

## ⚙️ Requirements

- Windows 10 or Windows 11
- Administrator privileges (launchers auto-request via UAC)
- PowerShell 5.0+ (built into Windows)

---

## 🔒 How to Run (if blocked by execution policy)

If Windows blocks the `.ps1` directly, use the `.cmd` launchers — they bypass execution policy automatically.

Or open **PowerShell as Administrator** and run:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Auto-Fix-WakeFromSleep.ps1
```

---

## 🖥️ BIOS Setting (if scripts don't fully fix it)

Some laptops block USB wake at the hardware level. Go to BIOS/UEFI:

> **Restart → F2 / Del / F10 during boot → Power → Advanced → ACPI**

Look for and **Enable**:
- `USB Wake Support`
- `USB Keyboard Wake`
- `USB Mouse Wake`
- `Power On By USB`

---

## 📝 Notes

- **Disabling hibernate** also disables Fast Startup (boot may be ~5–10 sec slower)
- **Wake on LAN** is disabled — re-enable if you use remote wake features
- Scripts are safe to re-run anytime — they check current state before applying fixes
