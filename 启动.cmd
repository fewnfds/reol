@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0"
set "launch_code=0"

echo.
echo  Reol
echo  ========================================
echo  1. 能力练习场（当前源码／范例配装）
echo  2. 百人宗门（当前源码／正常开局）
echo  3. Godot 编辑器
echo  0. 退出
echo.
choice /C 1230 /N /M "请选择 [1-3, 0]："
if errorlevel 4 goto finish
if errorlevel 3 goto editor
if errorlevel 2 goto world
if errorlevel 1 goto combat
goto finish

:combat
python tools\godot.py run -- --combat-lab=true
set "launch_code=%errorlevel%"
goto finish

:world
python tools\godot.py run
set "launch_code=%errorlevel%"
goto finish

:editor
python tools\godot.py editor
set "launch_code=%errorlevel%"

:finish
if not "%launch_code%"=="0" pause
popd
endlocal & exit /b %launch_code%
