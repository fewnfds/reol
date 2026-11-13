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

## 自动容量搜索

```powershell
python tools/capacity.py
python tools/capacity.py --speeds 8 16 --resolution 50 --out logs/capacity-high-rates
python tools/capacity.py --seed-report logs/前次目录/summary.json --out logs/capacity-new-build
```

程序自动跑1×/2×/4×/8×/16×，每个倍率指数增加人数探边，再二分并以独立更长窗口确认通过/不通过区间；不是手工不断轮询。只使用同一exe/pck的真实release窗口，窗口串行，期间换包会停止；每个子进程有短的装配/采样超时，退出或中断清理自己启动的进程。`--help`查看人口范围、分辨率、采样/确认时长、帧率和判据，默认搜索可配置上限，不把到达配置上限说成已测到硬件极限。

`--seed-report`只把旧报告中的人数当作候选起点，两端都在当前构建重新长窗测量，不继承任何通过结果。适合改版后的边界复核或失效试验后的重新取样，避免从最小人数重复整段探边。实际迷雾/镜头与预期配置不符时窗口直接作废，不能继续混用不同视图的人数结果。

`capacity-v1`固定全视图与镜头，沿原混合场景初始化充足生命/需求/木料和长施工，防止高倍速下减员或任务耗尽。固定战斗/施工群，其余继续个人观察、探索、采运，部分人物穿戴样例装备；人数不表示所有人同时战斗。忙碌比例统计移动/工作与原地战斗，不把原地攻击者当成闲置。零死亡、资源守恒和活动下限是有效负载检查，失效窗口单独报错，不伪装成人数不达标。

同一窗口分别评估满倍率与流畅档：全窗及前后半窗的实际/请求比值、无新增追赶需求截断；流畅档再加平均FPS及帧时P99。门槛可在CLI调整，实际值随`summary.json`保存；它是明确的工程容差，不是宣称精确锁帧或普遍极值。结果实时增量写入新建目录的`summary.json`、`report.md`和每窗JSON/日志/CPU样本，中断仍保留已经完成的结果，不覆盖旧测量。独立机器/负载和长局需另测；自动报告的两种区间不等于全部单位都在玩家视野内的战斗极限。

`step_mean_ms`由全窗累计成本差得到；`step_ms`分位数仍是原有有界尾部窗口，报告用`step_percentile_samples/measured_steps`标明覆盖率，不为统计扩大每步复制量。额外记录分段流速/交付/伤害、活动比例、镜头、打开窗口和原生渲染CPU/GPU时间；这些诊断不改变结算频率。单独一窗可用`benchmark.py --capacity`，搜索结果只归[BASELINE](../../status/baseline.md)。

短检查默认15秒进程上限，无旧分片、长回归或`check`命令；策略见[验证方式](../workflow/testing.md)。
