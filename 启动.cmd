@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0"
set "launch_code=0"
set "current_build=build\windows\act-p2\reol-act.exe"

echo.
echo  Reol
echo  ========================================
echo  1. 战斗试玩（最新源码）
echo  2. 普通世界（最新源码）
echo  3. 当前成品包（战斗练习，无需 Godot）
echo  4. Godot 编辑器
echo  0. 退出
echo.
choice /C 12340 /N /M "请选择 [1-4, 0]："
if errorlevel 5 goto finish
if errorlevel 4 goto editor
if errorlevel 3 goto release
if errorlevel 2 goto world

:combat
python tools\godot.py run -- --combat-lab=true
set "launch_code=%errorlevel%"
goto finish

:world
python tools\godot.py run
set "launch_code=%errorlevel%"
goto finish

:release
if not exist "%current_build%" (
    echo 未找到当前成品包：%current_build%
    set "launch_code=1"
    goto finish
)
start "" "%current_build%" -- --combat-lab=true
set "launch_code=%errorlevel%"
goto finish

:editor
python tools\godot.py editor
set "launch_code=%errorlevel%"

:finish
if not "%launch_code%"=="0" pause
popd
endlocal & exit /b %launch_code%
