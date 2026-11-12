# 运行与测量

在仓库根目录运行，Godot目标版本见[BASELINE](../../status/baseline.md)。

```powershell
python tools/godot.py doctor
python tools/godot.py import
python tools/godot.py run
python tools/godot.py test
python tools/godot.py export --preset "Windows Demo" --output build/windows/reol-demo.exe
```

`run`和Windows Demo均进入同一内核，默认24人普通开局，每次启动新局；F5/F9主动保存/加载当前格式。包为`build/windows/reol-demo.exe`及同目录pck，键位/试玩路线查[FEATURES](../../status/features.md)。

## 开发期直接试玩

双击仓库根目录的[开发试玩.cmd](../../../开发试玩.cmd)，或执行上面的`python tools/godot.py run`，直接从源码启动，不经过导出。修改后关闭窗口、再次启动即可读取最新脚本和shader；F5保存、重开后F9读取可以接续当前格式会话。

现有导出exe/pck是生成当时的快照，不会自动读取源码修改。开发试玩以源码入口为准，只有需要独立分发或release性能测量时才重新导出。这个入口不承诺在运行中热替换持有世界的线程与状态。

需要Godot编辑器时执行`python tools/godot.py editor`，F5运行、F8停止。官方[外部编辑器说明](https://docs.godotengine.org/en/4.7/tutorials/editor/external_editor.html)支持开启“Auto Reload Scripts on External Change”让编辑器读取外部改动；编辑器重载脚本与整个活世界无需重启是两回事。

## 实际性能

```powershell
python tools/benchmark.py --actors 1000 --speed 4 --fps 60 --seconds 15
python tools/benchmark.py --actors 1000 --speed 4 --fps 60 --mixed
python tools/benchmark.py --actors 1000 --speed 4 --fps 60 --mixed --fog
python tools/benchmark.py --actors 24 --speed 1 --fps 120 --screenshot
python tools/benchmark.py --actors 1000 --speed 4 --fps 60 --workers 0
```

采样器使用已导出的release，默认`build/windows/reol-demo.exe`，`--binary PATH`可固定构建。3秒运行预热，默认采样20秒，可用`--seconds`设5..60秒；装配/预热不计世界倍率。记录实际世界推进、步数/帧时、路径与交付、战斗/植物、材料审计、GPU绘制、线程及有界CPU/内存采样。CPU采样含装配，不能把整进程CPU秒直接当测量窗计算。

千人及以上默认全图开发视图，`--fog`强制玩家迷雾显示，不停止远处模拟。`--mixed`在同一后端冷装配100名持续交战者、20个真实材料施工与4次真实交换，其余人物继续生活；战斗HP与施工时长是明确压力配置，不是游戏平衡或第二套算法。小于150人不装配这组压力。

默认`--gpu-index 1`对应本机5060Ti；其他机器核对Godot输出后选实际设备。`--workers -1`按独立页/处理器自适应，0为同算法串行；少量一页会选择直接执行，不为了占满核心制造调度工作。JSON、日志、CPU采样和可选截图留在忽略的logs，报告含exe/pck哈希与当时Git状态。

直接运行exe可附`-- --actors=1000 --speed=4 --fps=60 --mixed=true --fog=true`；有界采样加`--duration=15 --warmup=3 --metrics=绝对路径`。同构建窗口串行跑，避免争用设备。headless只验证规则/CPU，不证明真实FPS。

短检查默认15秒进程上限，无旧分片、长回归或`check`命令；策略见[验证方式](../workflow/testing.md)。
