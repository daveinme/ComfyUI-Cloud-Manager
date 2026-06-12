@echo off
:: ============================================================
::  ComfyUI Cloud Manager — one-click install & launch
::  Windows (cmd / double-click)
:: ============================================================
title ComfyUI Cloud Manager Setup
cd /d "%~dp0"

echo.
echo ╔══════════════════════════════════════════════════════╗
echo ║        ComfyUI Cloud Manager — Setup                ║
echo ╚══════════════════════════════════════════════════════╝
echo.

:: ── 1. Check Node.js ───────────────────────────────────────
where node >nul 2>&1
if errorlevel 1 (
    echo [WARN] Node.js not found.
    echo.
    echo   Please install Node.js ^(v18 or newer^) from:
    echo   https://nodejs.org/en/download
    echo.
    start https://nodejs.org/en/download
    echo Press any key to exit after installing Node.js, then re-run this script.
    pause >nul
    exit /b 1
)

for /f "tokens=*" %%v in ('node -e "process.stdout.write(process.versions.node)"') do set NODE_VER=%%v
echo [OK] Node.js %NODE_VER%

:: ── 2. Install dependencies ─────────────────────────────────
set FIRST_RUN=0
if not exist "node_modules\" (
    set FIRST_RUN=1
    echo.
    echo Installing dependencies ^(first run, may take a minute^)...
    call npm install --prefer-offline
    if errorlevel 1 ( echo [ERR] npm install failed. & pause & exit /b 1 )
    echo [OK] Dependencies installed
) else (
    echo [OK] Dependencies already present
)

:: ── 3. Desktop shortcut (first run only) ─────────────────────
if "%FIRST_RUN%"=="1" (
    echo.
    powershell -NoProfile -Command ^
        "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\ComfyUI Cloud Manager.lnk'); $s.TargetPath = '%~dp0start.bat'; $s.IconLocation = '%~dp0assets\icon.ico'; $s.WorkingDirectory = '%~dp0'; $s.Save()"
    echo [OK] Desktop shortcut created — use start.bat next time
)

:: ── 4. Launch app ───────────────────────────────────────────
echo.
echo [OK] Launching ComfyUI Cloud Manager...
echo.
call npm start
