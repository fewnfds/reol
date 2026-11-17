@echo off
setlocal
chcp 65001 >nul
pushd "%~dp0"
set "launch_code=0"
set "current_build=build\windows\sect-foundation\reol-sect.exe"
set "legacy_combat_build=build\windows\act-p5\reol-act.exe"

echo.
echo  Reol
echo  ========================================
echo  1. 能力练习场（当前框架／范例配装）
echo  2. 百人宗门（最新源码）
echo  3. 百人宗门成品（无需 Godot）
echo  4. Godot 编辑器
echo  5. 历史版本：旧 P5 战斗包（保留旧存档）
echo  0. 退出
echo.
choice /C 123450 /N /M "请选择 [1-5, 0]："
if errorlevel 6 goto finish
if errorlevel 5 goto legacy_combat
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
start "" "%current_build%"
set "launch_code=%errorlevel%"
goto finish

:legacy_combat
if not exist "%legacy_combat_build%" (
    echo 未找到旧战斗包：%legacy_combat_build%
    set "launch_code=1"
    goto finish
)
start "" "%legacy_combat_build%" -- --combat-lab=true
set "launch_code=%errorlevel%"
goto finish

:editor
python tools\godot.py editor
set "launch_code=%errorlevel%"

:finish
if not "%launch_code%"=="0" pause
popd
endlocal & exit /b %launch_code%
