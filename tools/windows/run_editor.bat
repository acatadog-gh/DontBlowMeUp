@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0..\.." || (echo [ERROR] cannot enter project root & pause & exit /b 1)
call "%~dp0_find_godot.bat"
if errorlevel 1 (popd & pause & exit /b 1)
if not exist ".godot" call :import_once

echo Project : %CD%
echo Godot   : %GODOT_UI%
echo Opening Godot editor ...
start "" "%GODOT_UI%" --path "%CD%" -e
popd

exit /b 0

:import_once
echo First run: importing project ^(one-off, ~10 seconds^) ...
"%GODOT_CONSOLE%" --headless --path "%CD%" --import >nul 2>&1
exit /b 0
