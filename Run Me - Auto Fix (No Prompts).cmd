@echo off
:: =====================================================
::  Sleep & Wake -- AUTO FIX (No prompts, just fixes)
::  Double-click to run. Auto-requests Admin rights.
:: =====================================================

>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B
)

pushd "%~dp0"
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Auto-Fix-WakeFromSleep.ps1"
pause
