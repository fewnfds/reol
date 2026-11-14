@echo off
setlocal
pushd "%~dp0"
python tools\godot.py run -- --combat-lab=true %*
if errorlevel 1 pause
popd
endlocal
