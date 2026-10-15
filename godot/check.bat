@echo off
rem One command that proves the project is healthy: import, run every test, run a headless game.
rem Fails on: any failed test, no tests found, any engine/script error line, a headless run that
rem does not end with run_end. Output kept in .check-output.txt (git-ignored).
setlocal
set "GODOT="
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
  for %%F in ("%%D\Godot_v*-stable_win64_console.exe") do set "GODOT=%%~fF"
)
if "%GODOT%"=="" (
  echo CHECK FAILED: Godot not found. Install with: winget install GodotEngine.GodotEngine
  exit /b 2
)
set "HERE=%~dp0."
set "OUT=%~dp0.check-output.txt"
set "RUNLOG=%~dp0.check-run.log"

echo == import > "%OUT%"
"%GODOT%" --headless --path "%HERE%" --import >> "%OUT%" 2>&1

echo == tests >> "%OUT%"
"%GODOT%" --headless --path "%HERE%" --script res://tests/run_tests.gd >> "%OUT%" 2>&1
set "TEST_RC=%ERRORLEVEL%"

echo == headless run >> "%OUT%"
"%GODOT%" --headless --path "%HERE%" -- --seed=7 --ticks=600 "--log=%RUNLOG%" >> "%OUT%" 2>&1
set "RUN_RC=%ERRORLEVEL%"

type "%OUT%"
findstr /C:"SCRIPT ERROR" /C:"Parse Error" /C:"ERROR:" "%OUT%" >nul && (
  echo CHECK FAILED: engine or script errors in output above
  exit /b 1
)
if not "%TEST_RC%"=="0" (
  echo CHECK FAILED: tests exit code %TEST_RC%
  exit /b 1
)
if not "%RUN_RC%"=="0" (
  echo CHECK FAILED: headless run exit code %RUN_RC%
  exit /b 1
)
findstr /C:"run_end" "%RUNLOG%" >nul || (
  echo CHECK FAILED: headless run log has no run_end line
  exit /b 1
)
echo CHECK OK
exit /b 0
