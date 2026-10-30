@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
pushd "%~dp0..\.." || (echo [ERROR] cannot enter project root & pause & exit /b 1)
call "%~dp0_find_godot.bat"
if errorlevel 1 (popd & pause & exit /b 1)

rem --- use absolute paths for built-in tools: Git Bash / MSYS may shadow
rem     find.exe / timeout.exe / sort.exe with GNU versions on PATH ---
set "SYS=%SystemRoot%\System32"
set "FIND=%SYS%\find.exe"
set "FINDSTR=%SYS%\findstr.exe"
set "PING=%SYS%\ping.exe"
set "NETSTAT=%SYS%\netstat.exe"
set "TASKKILL=%SYS%\taskkill.exe"

set "TMPD=%TEMP%\dbmu_selftest"
if exist "%TMPD%" rd /s /q "%TMPD%" >nul 2>&1
mkdir "%TMPD%" >nul 2>&1
set "SMOKE_PORT=8933"

if not exist ".godot" (
    echo First run: importing project ^(one-off, ~10 seconds^) ...
    "%GODOT_CONSOLE%" --headless --path "%CD%" --import >nul 2>&1
)

echo Project : %CD%
for /f "delims=" %%v in ('"%GODOT_CONSOLE%" --version') do echo Godot   : %%v
echo.

echo -- 1/4 hotseat logic ------------------------------
"%GODOT_CONSOLE%" --headless --path "%CD%" -s tests/run_tests.gd > "%TMPD%\hotseat.log" 2>&1
set "P1=0"
set "F1=0"
for /f %%n in ('type "%TMPD%\hotseat.log" ^| "%FINDSTR%" /c:"PASS" ^| "%FIND%" /c /v ""') do set "P1=%%n"
for /f %%n in ('type "%TMPD%\hotseat.log" ^| "%FINDSTR%" /c:"FAIL" ^| "%FIND%" /c /v ""') do set "F1=%%n"
echo    PASS !P1! / FAIL !F1!    (baseline 99 / 0)

echo -- 2/4 online logic -------------------------------
"%GODOT_CONSOLE%" --headless --path "%CD%" -s tests/test_online_logic.gd > "%TMPD%\online.log" 2>&1
set "P2=0"
set "F2=0"
for /f %%n in ('type "%TMPD%\online.log" ^| "%FINDSTR%" /c:"PASS" ^| "%FIND%" /c /v ""') do set "P2=%%n"
for /f %%n in ('type "%TMPD%\online.log" ^| "%FINDSTR%" /c:"FAIL" ^| "%FIND%" /c /v ""') do set "F2=%%n"
echo    PASS !P2! / FAIL !F2!    (baseline 76 / 0)

echo -- 3/4 UI regression -------------------------------
"%GODOT_CONSOLE%" --headless --path "%CD%" -s tests/test_hand_ui.gd > "%TMPD%\ui.log" 2>&1
set "P4=0"
set "F4=0"
for /f %%n in ('type "%TMPD%\ui.log" ^| "%FINDSTR%" /c:"PASS" ^| "%FIND%" /c /v ""') do set "P4=%%n"
for /f %%n in ('type "%TMPD%\ui.log" ^| "%FINDSTR%" /c:"FAIL" ^| "%FIND%" /c /v ""') do set "F4=%%n"
echo    PASS !P4! / FAIL !F4!    (baseline 18 / 0)

echo -- 4/4 end-to-end smoke ----------------------------
set "P3=0"
set "F3=0"
"%NETSTAT%" -ano | "%FINDSTR%" ":%SMOKE_PORT% " | "%FINDSTR%" LISTENING >nul 2>&1
if not errorlevel 1 (
    echo    SKIPPED - port %SMOKE_PORT% already in use
) else (
    start "dbmu-smoke-server" /min "%GODOT_CONSOLE%" --headless --path "%CD%" -s scripts/server/server_main.gd -- port=%SMOKE_PORT%
    "%PING%" -n 5 127.0.0.1 >nul
    "%GODOT_CONSOLE%" --headless --path "%CD%" -s tests/smoke_online.gd > "%TMPD%\smoke.log" 2>&1
    rem kill only the smoke server window (image-name kill would hit the user's own game window)
    "%TASKKILL%" /f /fi "WINDOWTITLE eq dbmu-smoke-server" >nul 2>&1
    for /f %%n in ('type "%TMPD%\smoke.log" ^| "%FINDSTR%" /b /c:"PASS" ^| "%FIND%" /c /v ""') do set "P3=%%n"
    for /f %%n in ('type "%TMPD%\smoke.log" ^| "%FINDSTR%" /c:"FAIL" ^| "%FIND%" /c /v ""') do set "F3=%%n"
    echo    PASS !P3! / FAIL !F3!    baseline: at least 2 / 0
)

echo.
echo ======== SUMMARY ========
echo    hotseat : PASS !P1! / FAIL !F1!   (99 / 0)
echo    online  : PASS !P2! / FAIL !F2!   (76 / 0)
echo    ui      : PASS !P4! / FAIL !F4!   (18 / 0)
echo    smoke   : PASS !P3! / FAIL !F3!   (at least 2 / 0)
echo.

set /a TF=F1+F2+F3+F4
set "OK=1"
if not !TF! EQU 0 set "OK=0"
if not !P1! EQU 99 set "OK=0"
if not !P2! EQU 76 set "OK=0"
if not !P4! EQU 18 set "OK=0"
if "!OK!"=="1" (
    echo    [OK] all green - safe to export
) else (
    echo    [FAIL] some FAIL lines, or a count differs from 99 / 76 / 18 - see logs below
    type "%TMPD%\hotseat.log" | "%FINDSTR%" "FAIL"
    type "%TMPD%\online.log"  | "%FINDSTR%" "FAIL"
    type "%TMPD%\ui.log"      | "%FINDSTR%" "FAIL"
    if exist "%TMPD%\smoke.log" type "%TMPD%\smoke.log" | "%FINDSTR%" "FAIL"
)

echo.
echo Logs: %TMPD%
popd
pause
