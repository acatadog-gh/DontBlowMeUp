@echo off
rem ============================================================
rem  Locate Godot 4.x on Windows and export GODOT_UI / GODOT_CONSOLE.
rem  Called by run_game / run_editor / run_online_test / run_tests.bat
rem  Search order:
rem    1. GODOT_UI_EXE / GODOT_EXE environment variables
rem    2. <project>\godot\Godot*_win64.exe      (portable drop-in)
rem    3. common install folders (godot-tools / Program Files / scoop ...)
rem    4. PATH  (godot.exe)
rem  Exits with errorlevel 1 when nothing usable is found.
rem ============================================================
set "GODOT_UI="
set "GODOT_CONSOLE="
set "GODOT_PORTABLE=%~dp0..\..\godot"

rem ---- 1) explicit overrides -----------------------------------
if exist "%GODOT_UI_EXE%" set "GODOT_UI=%GODOT_UI_EXE%"
if exist "%GODOT_EXE%"    set "GODOT_CONSOLE=%GODOT_EXE%"

rem ---- 2) portable drop-in -------------------------------------
if not defined GODOT_CONSOLE for %%f in ("%GODOT_PORTABLE%\Godot*_console.exe") do if exist "%%~ff" set "GODOT_CONSOLE=%%~ff"
if not defined GODOT_UI      for %%f in ("%GODOT_PORTABLE%\Godot*_win64.exe")   do if exist "%%~ff" set "GODOT_UI=%%~ff"

rem ---- 3) common install folders -------------------------------
for %%d in (
    "D:/godot-tools"
    "C:/godot-tools"
    "%ProgramFiles%\Godot"
    "%ProgramFiles(x86)%\Godot"
    "%LOCALAPPDATA%\Programs\Godot"
    "%USERPROFILE%\scoop\apps\godot\current"
    "%USERPROFILE%\Documents\godot"
) do (
    if not defined GODOT_CONSOLE for %%f in ("%%~d\Godot*_console.exe") do if exist "%%~ff" set "GODOT_CONSOLE=%%~ff"
    if not defined GODOT_UI      for %%f in ("%%~d\Godot*_win64.exe")   do if exist "%%~ff" set "GODOT_UI=%%~ff"
    if not defined GODOT_UI      for %%f in ("%%~d\godot.exe")          do if exist "%%~ff" set "GODOT_UI=%%~ff"
)

rem ---- 4) PATH --------------------------------------------------
if not defined GODOT_UI      for /f "delims=" %%p in ('where godot.exe 2^>nul')        do set "GODOT_UI=%%p"
if not defined GODOT_CONSOLE for /f "delims=" %%p in ('where godot_console.exe 2^>nul') do set "GODOT_CONSOLE=%%p"

rem ---- 5) derive the missing counterpart ------------------------
if defined GODOT_UI if not defined GODOT_CONSOLE set "GODOT_CONSOLE=%GODOT_UI:_win64.exe=_win64_console.exe%"
if defined GODOT_CONSOLE if not exist "%GODOT_CONSOLE%" set "GODOT_CONSOLE="
if defined GODOT_UI if not defined GODOT_CONSOLE set "GODOT_CONSOLE=%GODOT_UI%"
if defined GODOT_CONSOLE if not defined GODOT_UI set "GODOT_UI=%GODOT_CONSOLE:_console.exe=.exe%"
if defined GODOT_UI if not exist "%GODOT_UI%" set "GODOT_UI="
if defined GODOT_CONSOLE if not defined GODOT_UI set "GODOT_UI=%GODOT_CONSOLE%"

if not defined GODOT_UI (
    echo [ERROR] Godot 4.x not found. Any one of these fixes it:
    echo          1^) set GODOT_UI_EXE / GODOT_EXE to your Godot .exe
    echo          2^) unzip Godot into "%GODOT_PORTABLE%"
    echo          3^) add godot.exe to PATH
    exit /b 1
)
if not defined GODOT_CONSOLE set "GODOT_CONSOLE=%GODOT_UI%"
exit /b 0
