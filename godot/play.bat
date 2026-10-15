@echo off
rem Starts the game on PC (double-click this file). Finds the Godot installed by winget.
setlocal
set "GODOT="
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_*") do (
  for %%F in ("%%D\Godot_v*-stable_win64.exe") do set "GODOT=%%~fF"
)
if "%GODOT%"=="" (
  echo Could not find Godot. Install it with: winget install GodotEngine.GodotEngine
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
