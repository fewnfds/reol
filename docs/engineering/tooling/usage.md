# 运行与测量

在仓库根目录运行，Godot目标版本见[BASELINE](../../status/baseline.md)。

```powershell
python tools/godot.py doctor
python tools/godot.py import
python tools/godot.py run
python tools/godot.py test
python tools/godot.py test --suite equipment
python tools/godot.py export --preset "Windows Demo" --output build/windows/reol/reol.exe
```

`run`和新导出的Windows Demo默认进入同一100人青禾宗（玩家1＋99自主），每次启动新局；源码F5/F9主动保存/加载format33，默认`user://sect-quicksave-v33.reol`，旧32档保留。需要独立包时按上方示例从当前源码导出，键位与试玩路线查[FEATURES](../../status/features.md)。

## 开发期直接试玩

根目录只保留一个[启动.cmd](../../../启动.cmd)，所有日常入口在同一菜单中选择：

| 选项 | 用途 |
|---|---|
| 1 · 能力练习场 | 当前框架与范例配装，和宗门共用Combat |
| 2 · 百人宗门 | 运行最新源码的正常宗门开局 |
| 3 · Godot 编辑器 | 打开当前项目编辑器 |
| 0 · 退出 | 关闭启动菜单 |

源码运行共用`tools/godot.py`，修改后关闭窗口、再次启动即可读取最新脚本和shader；F5保存、重开后F9读取可以接续当前格式会话。维护脚本归`tools/`，按需生成的导出包归`build/windows/`。

ACT测试入口相当于`python tools/godot.py run -- --combat-lab=true`：同一512²世界保留后台生活，默认血刃＋轻重敌/射手混战；顶栏可切近远组合和基础范例或单轻敌/单重敌。切换会替换整个练习世界且不写存档。WASD、鼠标瞄准、左键主攻击、右键技能、E/C额外主动槽、空格闪步；Tab切日常／战斗，F附近交互；正常宗门默认日常，WASD仍可用，左键点选、右键对象菜单。普通世界按1/2装备铁剑或短弓，其中铁剑右键为重斩。练习场的血刃和守势剑配置右键为守势，范例由练习场顶栏选择。

Esc→设置可调整音量、震动、闪光和键位。历史 ACT P5 包和 format14 存档可用于复核历史样本，入口见[历史资料](../../archive/README.md)。

技能制作从`data/definitions/combat/library.tres`与其引用的`.tres`进入，编辑器“工具→Reol 战斗技能库”可直达；技能Inspector有阶段/范围预览，共同Resource有字段/引用校验与引用跳转。保存后关闭并重新运行游戏采用新定义，重练不重载；配置字段与制作流程见[规格10](../../../design/systems/combat_framework/act_and_barrage.md#101-定义施放和表现的接入合同)。短检查命令示例（`GODOT_EXE`为实际引擎路径）：

```powershell
& $env:GODOT_EXE --headless --path . --script tests/decisions_smoke.gd
& $env:GODOT_EXE --path . --script tests/decisions_ui_smoke.gd
& $env:GODOT_EXE --headless --path . --script tests/action_combinations_smoke.gd
& $env:GODOT_EXE --path . --script tests/action_combinations_ui_smoke.gd
& $env:GODOT_EXE --editor --path . --scene res://tests/combat_authoring_editor.tscn -- --combat-authoring-check
```

单位策略制作从`data/definitions/decisions/library.tres`进入，编辑器“工具→Reol 单位策略库”可直达，Policy/Rule沿同一Inspector校验与跳转；[绑定与扩展合同](../../../design/systems/unit_decision_framework.md#5-制作与绑定)。F12输入`decisions`查看最近选择、选中/玩家的模式、任务与拒绝；只读诊断不执行任意脚本。

设施作业位置在`data/definitions/construction.json`的`work_positions`配置，本格、四邻和指定工位共用接近与到场检查；实际示例和坐标旋转见[空间与施工](../../../design/systems/construction_and_space/places.md#定义与扩展)。交互模式选中灶台或放置预览时显示金色操作位，须留出通路。相关短检查可按需运行`tests/work_positions_smoke.gd`（headless）及`tests/work_positions_ui_smoke.gd`（真实图形），不加入默认kernel套件。

DEV可选开启“反应追踪”，再F12输入`actions`读取最近64条采用规则；默认关闭，读档/重练清空，不进存档。

编辑器检查使用一次性编辑进程并自动退出，未带最后的测试参数时测试场景不会运行检查。截图和日志仍归`logs/`；这些命令不新增启动CMD。

现有导出exe/pck是生成当时的快照，不会自动读取源码修改。开发试玩以源码入口为准，只有需要独立分发或release性能测量时才重新导出。这个入口不承诺在运行中热替换持有世界的线程与状态。

`logs/run-*.log`保留本次源码试玩输出，包括引擎错误、`SESSION_STATE`（实际暂停/倍率/会话切换）、`PLAYER_COMMAND`（指令与入队序号）、`COMMAND_RESULT`（接受或拒绝原因）和`PLAYER_OUTCOME`（玩家相关到达、失败、受击、死亡等结果）。不逐帧记录或打印全部NPC行为；游戏未关闭也可读取当前日志。原生引擎日志另在`%APPDATA%/Godot/app_userdata/reol/logs/godot.log`。

F12、右下角诊断条或DEV入口打开独立面板，Esc关闭。面板用Godot原生`Logger`接收主线程/后台线程的错误、警告和普通输出，错误附可取得的脚本位置与调用栈；无需编辑器连接。显示玩家本人HP/行动/位置、世界时间/暂停、模拟线程存活、快照年龄、在途/待受理指令、最近回执和当前UI焦点。`dead`、`blocked`等业务拒绝的完整原因在`COMMAND_RESULT`日志查看；普通UI用短暂叉号反馈。控制台支持`help/status/actions/decisions/errors/log/export`，只查看诊断；打开时世界继续运行，输入文字不会触发游戏键盘命令。

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

采样器默认使用`build/windows/reol/reol.exe`。测当前源码时可先按上面的命令重新导出。历史包或独立对照包可以显式通过`--binary`指定。采样器的`--actors=N`选择开发负载。正常宗门窗口直接运行新导出的exe并给`-- --opening=sect --duration=15 --warmup=3 --fps=60 --metrics=绝对路径`，不要把两种开局混算。3秒运行预热，默认采样20秒，可用`--seconds`设5..60秒；装配/预热不计世界倍率。记录实际世界推进、步数/帧时、路径与交付、战斗/植物、材料审计、GPU绘制、线程及有界CPU/内存采样。CPU采样含装配，不能把整进程CPU秒直接当测量窗计算。

新源码默认`--sim-hz 60`，20/100只供对照；JSON记录实际配置。`--combat-lab`选上述测试开局，不能与响应探针混用，普通与压力场景不混算。采样保持固定镜头，日常试玩默认跟随玩家。

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

每次使用同一exe/pck的真实release窗口串行测量，期间换包就停止。报告保留同人数的步均、主线程/GPU耗时与帧时变化百分比、实际倍率和粗略通过人数；历史上限只作参考，不声称重新测到了精确极限。硬件、人数、视图、worker、采样时长、场景标签或模拟频率不同会标记不可直接比较。改变场景内容或实际工作量时仍需人工说明，工具无法保证不同版本负载完全等价。

当前ACT压力场景标签为`capacity-act-v1`，历史`capacity-v1`保留；它们的攻击阶段、射速与相位切分不同，工具阻止直接输出成本变化百分比。60Hz的单步耗时也不能与旧50ms步直接相除。两者固定全视图与镜头，初始化充足生命/需求/木料和长施工；100名交战者与20名施工请求者以外的单位继续自主生活，约两成穿戴装备。检查零死亡、资源守恒及活动量，避免靠减员/闲置伪装性能；失效采样计入次数且不自动重试。

成本提示阈值和世界流速/画面判据可用--help查看并按任务调整；成本增加提示需要结合功能价值权衡。summary.json、report.md和每窗JSON/日志/CPU样本写在忽略的logs新目录，中断仍保留结果，子进程有超时并清理自身。可显式把一次完成的新summary作为后续--baseline；默认历史不会悄悄被退化结果覆盖。接受的新基线才更新唯一数值原件，BASELINE只维护解释与证据入口。

step_mean_ms由全窗累计成本差得到；step_ms分位数仍是有界尾部窗口。单独一窗可用benchmark.py --capacity；headless不能证明真实FPS，不因纯文档/工具改动重跑全部游戏倍率。

### 基础框架的持续战斗归因

`python tools/benchmark.py --binary build/windows/reol/reol.exe --actors 24 --speed 1 --fps 60 --workers -1 --seconds 5 --gpu-index 0 --fog --combat-probe --out logs/framework-capture.json`显式开启`framework-combat-v1`。只允许有界1×、至少4人，不与mixed/capacity/response混用；普通启动不启用。原P4星焰控制/动作在同一World中推进，三敌和玩家有明示耐久覆盖，后台正常生活。v1开局保留默认血刃到星焰的配置过渡，固定比较场景；不读取或保存用户世界。它不是手动输入延迟测量，也不与capacity标签混算。

报告`profile`含外层准备、身体、共同提交、环境/观察及全步累计，还有嵌套索引与发布计时、细段/索引/full次数。外层剩余可由全步减去互斥分项得到，索引子计时不能再相加。峰值仅为自开局在主步边界的观察，不是细段内或单独采样窗最大值；不输出峰值差。快profile与慢counters的边界可能相差几步，原值保留，不能据命中差1次判定规则改变。参考实现的固定步结果比较只用于本次改动，未设永久确定性门禁。

## 响应链实验

可选探针使用显式开启的合成移动请求，沿真实Runner邮箱、运动提交与原显示插值测量。先导出隔离release，保留正式试玩包：

```powershell
python tools/godot.py export --preset "Windows Demo" --output build/windows/response-probe/reol-response.exe
python tools/benchmark.py --binary build/windows/response-probe/reol-response.exe --actors 1 --speed 1 --fps 60 --seconds 25 --fog --response-probe --out logs/response-minimum.json
python tools/benchmark.py --binary build/windows/response-probe/reol-response.exe --actors 24 --speed 1 --fps 60 --seconds 25 --fog --response-probe --out logs/response-ordinary.json
```

两个窗口串行运行，地图/镜头/迷雾设置相同，正常世界仍有生活与按真实武器接敌的NPC。该开关只接受1×、有时限的普通开局，不与mixed/capacity/combat-lab混用；自动让本次新局的玩家在合法半格路段往返，不保存，不用于操作用户已有会话。报告单列`synthetic-move-response-v1`，不能拿它替换capacity-v1历史样本。

`response_chain`保存最多128次请求的明细、失败与分位数：请求→Runner开始处理、命令应用返回、回执发布、首次运动姿态提交、首次显示采样变化。命令应用返回只说明路线请求成立，不等于身体已经移动；运动姿态测点取现有`Pose.completed_usec`，包含构造姿态前的部分快照准备，不是独立的World内部提交计时。诊断信封在Runner内剥离，不进入世界动作或存档。每次等前一段结束再发起，变换发起间隔以减少与心跳/显示帧的固定相位重合。

显示测点使用人物原显示采样器、0.5屏幕像素位移阈值，表示CPU已经准备该姿态；不包含真实设备输入、GPU提交/显示器扫描，也不代表连招或闪避启动。`observed_pose_publish_interval_ms`是主线程看到的新姿态对应发布间隔，可能跳过未采用的中间帧，不冒充所有权威提交的完整间隔。长时间未采用导致首个运动姿态超出历史窗口时标记失败，不能以较晚姿态冒充首次提交。窗口末尾未完成请求单独标记，失败不进入成功分位数。用于判断旧链与候选高频链的相对变化，真实键鼠手感仍须图形试玩。

短检查默认15秒进程上限，无旧分片、长回归或`check`命令；策略见[验证方式](../workflow/testing.md)。

## 宗门周期日志分析

已有`settlement_cycle_smoke.gd`日志可直接离线分析，不启动游戏或读取存档：

```powershell
python -X utf8 tools/settlement_report.py logs/本次周期.log --output logs/本次周期-report.json
python -X utf8 tools/test_settlement_report.py
```

不给`--output`时写stdout；指定输出须为新文件且父目录已存在，拒绝覆盖原日志或旧报告。输入为一个进程的`NORMAL_SETTLEMENT` JSON行及可选`wall_ms`后缀，不拼接重启日志；缺字段、损坏JSON、计数回退或时间倒退会失败。只有一条样本可保留原值，但没有可算的区间。短运行未达120000ms报告边界时可能没有快照，工具会说明无样本。

`windows`按相邻实际时刻相减，`observed_span`按第一/末条相减；`actions_delta`是完成次数，`refusals_delta`还包含中断等非完成结果，不含所有规划落选原因。各院`resident_actions_delta`按居民编制归组，`spatial_items_delta`按当前坐标归组，含行人随身物，不当院落权属账本。

第一条不默认为时间0，样本间缺口不补帧，`lowest_sampled_through_end`是测试自身起点/恢复点以来已有的最低采样，可能早于本次区间。终止行`final`不解析，末条快照可能早于实际停止；原`SMOKE/PARTIAL`与错误行单独保留。工具退出0仅表示分析成功，没有观测原进程退出码，也不证明长局/FPS/队列公平。`*_usec`可能嵌套/跨线程，不相加成CPU占用；比较还须人工固定构建、开局、数据/种子及步进/worker条件。当前固定metrics若新增字段，须先分类为累计计数或当前量再更新消费者。方法与限制见[实验说明](../simulation-methods.md#现有宗门日志的离线分窗)。

## 按主题短检查

`test`默认只跑kernel核心；`--suite features`、`--suite sight`、`--suite equipment`分别运行原有专题，同样使用15秒上限。完整检查地图见[tests](../../../tests/README.md)，按改动选用，不自动串成长矩阵。
