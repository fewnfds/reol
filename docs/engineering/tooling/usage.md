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

`logs/run-*.log`保留本次源码试玩输出，包括引擎错误、`SESSION_STATE`（实际暂停/倍率/会话切换）、`PLAYER_COMMAND`（指令与入队序号）、`COMMAND_RESULT`（接受或拒绝原因）和`PLAYER_OUTCOME`（玩家相关到达、失败、受击、死亡等结果）。不逐帧记录或打印全部NPC行为；游戏未关闭也可读取当前日志。原生引擎日志另在`%APPDATA%/Godot/app_userdata/reol/logs/godot.log`。

F12、右下角诊断条或DEV入口打开独立面板，Esc关闭。面板用Godot原生`Logger`接收主线程/后台线程的错误、警告和普通输出，错误附可取得的脚本位置与调用栈；无需编辑器连接。显示玩家本人HP/行动/位置、世界时间/暂停、模拟线程存活、快照年龄、在途/待受理指令、最近回执和当前UI焦点。`dead`、`blocked`等业务拒绝的完整原因在`COMMAND_RESULT`日志查看；普通UI用短暂叉号反馈。控制台支持`help/status/errors/log/export`，只查看诊断；打开时世界继续运行，输入文字不会触发游戏键盘命令。

“导出诊断”将当前状态和最近512条日志写入`%APPDATA%/Godot/app_userdata/reol/diagnostics/reol-*.json`，也可复制到剪贴板；不覆盖存档。窗口最多显示最近120条匹配记录，计数是本次进程累计值，完整引擎输出仍查原日志。关闭面板时只低频更新计数；回调只写有界缓存，不在模拟线程处理UI/文件。捕获从autoload进入后开始，无法收取更早的引擎启动信息；脚本在注册前就解析失败时仍需查引擎文件日志。已有独立运行进程不能热装此面板，重开源码试玩才生效。

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

采样工具默认显式全图开发视图，`--fog`选择玩家迷雾显示，不停止远处模拟；直接打开游戏仍按普通试玩默认，二者不混用。`--mixed`在同一后端冷装配100名持续交战者、20个真实材料施工与4次真实交换，其余人物继续生活；战斗HP与施工时长是明确压力配置，不是游戏平衡或第二套算法。小于150人不装配这组压力。

默认`--gpu-index 1`对应本机5060Ti；其他机器核对Godot输出后选实际设备。`--workers -1`按独立页/处理器自适应，0为同算法串行；少量一页会选择直接执行，不为了占满核心制造调度工作。JSON、日志、CPU采样和可选截图留在忽略的logs，报告含exe/pck哈希与当时Git状态。

直接运行exe可附`-- --actors=1000 --speed=4 --fps=60 --mixed=true --fog=true`；有界采样加`--duration=15 --warmup=3 --metrics=绝对路径`。同构建窗口串行跑，避免争用设备。headless只验证规则/CPU，不证明真实FPS。

## 功能性能对照

```powershell
python tools/capacity.py
python tools/capacity.py --speeds 4 16 --max-trials 1
python tools/capacity.py --baseline logs/performance-前次目录/summary.json
```

入口沿用capacity.py，现已改为轻量历史对照，不再指数探边/二分/长窗确认。默认读取已入库的[performance.json](../../status/performance.json)，在历史同人数运行；正常结果就停止，可疑成本增加只复核一次，不能满速才粗略降档，单倍率至多3个窗口。--speeds选择相关倍率，--max-trials可以进一步减量；--seconds默认沿历史样本时长。策略只在[开发循环](../workflow/testing.md#性能回归)维护。

每次使用同一exe/pck的真实release窗口串行测量，期间换包就停止。报告保留同人数的步均、主线程/GPU耗时与帧时变化百分比、实际倍率和粗略通过人数；历史上限只作参考，不声称重新测到了精确极限。硬件、人数、视图、worker、采样时长不同会标记不可直接比较。改变场景内容或实际工作量时仍需人工说明，工具无法保证不同版本负载完全等价。

capacity-v1固定全视图与镜头，初始化充足生命/需求/木料和长施工；100名交战者与20名施工请求者以外的单位继续自主生活，约两成穿戴装备。检查零死亡、资源守恒及活动量，避免靠减员/闲置伪装性能；失效采样计入次数且不自动重试。

成本提示阈值和世界流速/画面判据可用--help查看并按任务调整；成本增加提示需要结合功能价值权衡。summary.json、report.md和每窗JSON/日志/CPU样本写在忽略的logs新目录，中断仍保留结果，子进程有超时并清理自身。可显式把一次完成的新summary作为后续--baseline；默认历史不会悄悄被退化结果覆盖。接受的新基线才更新唯一数值原件，BASELINE只维护解释与证据入口。

step_mean_ms由全窗累计成本差得到；step_ms分位数仍是有界尾部窗口。单独一窗可用benchmark.py --capacity；headless不能证明真实FPS，不因纯文档/工具改动重跑全部游戏倍率。

短检查默认15秒进程上限，无旧分片、长回归或`check`命令；策略见[验证方式](../workflow/testing.md)。
