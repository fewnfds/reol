# 运行与测量

在仓库根目录运行，Godot目标版本见[BASELINE](../../status/baseline.md)。

```powershell
python tools/godot.py doctor
python tools/godot.py import
python tools/godot.py run
python tools/godot.py test
python tools/godot.py export --preset "Windows Demo" --output build/windows/reol-demo.exe
```

`run`和唯一Windows Demo都进入同一内核。试玩包为`build/windows/reol-demo.exe`及同目录pck；默认千人有限世界，键位查[FEATURES](../../status/features.md)。每次启动新局，当前没有SL。

## 实际性能

```powershell
python tools/benchmark.py --actors 1000 --speed 4 --fps 60 --seconds 20
python tools/benchmark.py --actors 1000 --speed 4 --fps 30 --workers 0
python tools/benchmark.py --actors 10000 --speed 4 --fps 60 --out logs/capacity.json --screenshot
```

采样器使用已导出的release，默认`build/windows/reol-demo.exe`；`--binary PATH`可固定同一构建。3秒运行预热后采样20秒，准备/预热不计世界倍率。记录实际世界推进、步数、资源工作量/守恒、帧时、GPU绘制、批参与线程及有界CPU/内存采样；后者包含装配，不能把整进程CPU秒直接当采样窗计算。

默认`--gpu-index 1`对应本机5060Ti；其他电脑先检查Godot输出并选择实际设备，不把索引当通用硬件约定。`--workers -1`按独立页/处理器自适应，0为串行对照。输出JSON/日志/截图留在忽略的logs。

必要时可直接运行exe并附带`-- --actors=1000 --speed=4 --fps=60`；`--duration=20 --warmup=3 --metrics=绝对路径`用于有界采样。headless只能说明CPU/规则，不证明真实帧率。相同构建的独立窗口串行跑，避免几场游戏争用设备。

短检查默认15秒进程上限，不再有旧分片/长回归/3600秒等待；检查策略见[验证方式](../workflow/testing.md)。
