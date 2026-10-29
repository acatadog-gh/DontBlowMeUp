@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
pushd "%~dp0..\.." || (echo [ERROR] cannot enter project root & pause & exit /b 1)
call "%~dp0_find_godot.bat"
if errorlevel 1 (popd & pause & exit /b 1)

rem --- use absolute paths for built-in tools: Git Bash / MSYS may shadow them ---
set "SYS=%SystemRoot%\System32"
set "FINDSTR=%SYS%\findstr.exe"
set "PING=%SYS%\ping.exe"
set "NETSTAT=%SYS%\netstat.exe"
set "PORT=8920"

if not exist ".godot" (
    echo First run: importing project ^(one-off, ~10 seconds^) ...
    "%GODOT_CONSOLE%" --headless --path "%CD%" --import >nul 2>&1
)

echo Project : %CD%
for /f "delims=" %%v in ('"%GODOT_CONSOLE%" --version') do echo Godot   : %%v
echo.

"%NETSTAT%" -ano | "%FINDSTR%" ":%PORT% " | "%FINDSTR%" LISTENING >nul 2>&1
if not errorlevel 1 (
    echo [WARN] port %PORT% already listening - reusing the existing server
    echo        close that window first if you want a fresh server
) else (
    echo Starting server ws://127.0.0.1:%PORT% in a new window ...
    start "dbmu-server-%PORT%" "%GODOT_CONSOLE%" --headless --path "%CD%" -s scripts/server/server_main.gd -- port=%PORT%
    "%PING%" -n 4 127.0.0.1 >nul
)

echo Starting client 1 ...
start "" "%GODOT_UI%" --path "%CD%" res://scenes/net_main.tscn
"%PING%" -n 3 127.0.0.1 >nul
echo Starting client 2 ...
start "" "%GODOT_UI%" --path "%CD%" res://scenes/net_main.tscn

echo.
echo Steps:
echo   1^) window 1: nickname -^> Create Room -^> note the 6-digit invite code
echo   2^) window 2: nickname -^> type the invite code -^> Join
echo   3^) window 1: once 2 players are listed, click Start
echo.
echo Reminder: after changing SERVER code, close the server window and re-run this file.
echo.
popd
pause
