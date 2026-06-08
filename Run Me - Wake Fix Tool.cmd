@echo off
:: ========================================================
::  Wake From Sleep Fix Tool — Launcher
::  Double-click this file to run the diagnostic tool
:: ========================================================

:: Request admin elevation automatically
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting Administrator privileges...
    goto UACPrompt
) else (
    goto gotAdmin
)

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%~dp0"

:: Run the PowerShell script
powershell.exe -ExecutionPolicy Bypass -File "%~dp0Fix-WakeFromSleep.ps1"

pause
