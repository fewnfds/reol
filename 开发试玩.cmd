@echo off
setlocal
pushd "%~dp0"
python tools\godot.py run %*
if errorlevel 1 pause
popd
endlocal
