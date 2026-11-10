# 工具链与运行入口

状态：当前操作入口。实际安装及已验范围由[AI套件实装](setup.md)维护，版本与来源/更新流程见[维护记录](maintenance.md)，代码审查/CI成本策略见[工作流](../workflow/code-review.md)。本页不重复旧竞品表或宣称导出已验。完整旧文已存[整理前快照](../../archive/documentation_consolidation_20261104/docs/TOOLCHAIN.md)。

Godot跟进最新稳定版；当前已核对的是**4.7.2**，不是永久锁定。每次升级要核对编辑器、插件、CI及导出模板的实际版本与兼容；不要自动使用dev/RC。优先[官方Windows下载](https://godotengine.org/download/windows/)的标准版，不使用.NET版。可用GODOT_BIN指向具体可执行文件；设置用户环境变量后需重启读取它的进程。

## 项目命令

~~~powershell
python tools/godot.py doctor
python tools/godot.py version
python tools/godot.py import
python tools/godot.py test --list-suites
python tools/godot.py test --suite test_environment_field_rules --test-timeout 120
python tools/godot.py test --test-timeout 1800
python tools/godot.py check --test-timeout 1800
python tools/godot.py run
python tools/godot.py editor
python tools/check_structure.py
python -X utf8 -m unittest discover -s tests -p "test_*.py" -v
python tools/setup_codex.py --check --review-model gpt-6.1-sol
~~~

check包括结构、导入和统一同步测试runner；test不替代导入，测试超时或任何首个真实脚本错误均非通过。命令及作用域、画面/存读验收见[测试入口](../../../tests/README.md)。导出到Windows还需匹配引擎的模板、实际导出预设及独立运行验证，不能凭命令存在就认定已可发布。

定向`test --suite`按完整名称选择，可重复；`check`保持全套。逐组耗时和断言增量默认写到唯一`logs/*-timings-*.jsonl`，可用`--timing-report PATH`指定。报告逐组flush，失败/超时后读一次即可，不需要扫描testlog；验证分层与GPU边界见[测试策略](../workflow/testing.md)。

## 配置和观察

试玩HUD顶部常显FPS、帧间隔/当前2秒窗口峰值及世界流速；F3展开/收起完整诊断。FPS复用Godot的`Engine.get_frames_per_second()`，与编辑器Debugger → Monitors的原生指标同类，每秒更新；帧间隔用单调宿主时钟，包括显示等待及调度，不能冒充GPU时间。采样只持固定标量，标签2Hz刷新，暂停不停止采样。需要追踪耗时用编辑器Debugger → Profiler/Visual Profiler；原生`--print-fps`只向stdout输出FPS。API依据[Engine](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine-method-get-frames-per-second)与[Performance](https://docs.godotengine.org/en/4.7/classes/class_performance.html)。

Demo性能诊断独立于普通入口：`python tools/diagnose_demo.py --seconds 120`启动一个新的普通Main试玩进程，不接管已运行的游戏。正常选择人生、移动和交互；采样到时停止并恢复原回调，游戏继续运行，关闭窗口也会落盘。1–300秒有界采样，默认120秒；`--auto-start --quit-after-capture`仅供自动选择人身并在采样后关闭该新进程的QA。`--headless`只能验证工具，不证明画面性能。

报告在忽略的`logs/demo-profile-*.json`及同名JSONL，每秒写入一条窗口记录并flush；保留最多20000帧样本和24个最大帧现场。报告包含源码SHA/dirty、请求与实际推进、负载倍率/欠算、原结算步骤调用次数/累计与最长耗时、运行层剩余耗时、迷雾更新/地块加载标记。暂停、等候与加载切换不计入正常流速比值。步骤以外的剩余时间包含区域推进、调度和视图刷新，不能冒称某单一模块；迷雾/加载标记表示相关性，非直接耗时。

实装在`tools/diagnostics/demo_recorder.gd`，由`tools/qa/demo_diagnostics.gd`单独装配，普通Main不加载。只包装原Callable并原样返回，不改变阶段顺序、事件、输入、预算、存档或领域状态；读档更换内核后重新挂接，结束时恢复原回调。这是有测量开销的开发诊断，不是发布版/GPU时间或整机性能证明；针对疑似显示热点继续使用Godot原生Profiler。

临时人口压力入口为`python tools/stress_demo.py --residents 50 --seconds 30`：两地各50人，共100个人物身体；普通Main不加载该入口。真实实例使用原定义、原寻路、生活、环境和共同时间，抵达后通过原取消/提交命令在四处持续巡行，采样后可继续试玩。`--quit-after-capture`自动退出，`--opening-wave`复现单次去宿舍的旧对比负载；`--headless`不证明渲染表现。每地6–256人，采样5–300秒。临时派生运行层拒绝普通保存/读取，既有玩家档不参与。

压力报告为`logs/crowd-人数-时间.json`与同名JSONL，复用原诊断并增加实际移动人数、巡行重下命令数、采样期间处于travel阶段的平均人数；后者不是逐帧速度测量。指令装配和诊断自身会占用宿主，累计结算计时不包括压力控制器的输入成本，帧间隔包括它。开发可执行文件、密集持续移动与普通生活负载分别声明，不能用人数或一次移动成功冒称规模达标。

- 首选实时场景连接为Godot AI：编辑器启用插件后用官方dock的Configure → Codex生成带认证的attach，重载后实际核查Reol会话、日志和运行状态；不手写端口/裸HTTP，不更改第三方addon。当前实现与过滤范围见[套件实装](setup.md)。
- python tools/setup_codex.py 补项目中的Context7和默认禁用的Coding-Solo备用入口；已存在连接和无关配置保留。仅在明确需要备用时用 --enable-backup-godot；显式 --review-model gpt-6.1-sol 设置项目审查模型，--check只验证配置而不证实握手。项目配置/备份不入库；用户级路由与认证不在此脚本中改写。
- API以当前目标版本的Godot官方文档为准，Context7可辅助查询。旧opencode.json属于旧客户端，不是Codex生效配置。
- GitHub的Python及Godot CI证据按完整受检SHA核对。仅在准备实际提交时由主代理按[CI流程](../workflow/code-review.md)集中检查一次；未终态留到下次提交，不开后台等待或派被动代理。300秒缓存是限频底线，不是轮询周期；当前无GitHub结果自动插入聊天的回调。

## 排错和升级

| 现象 | 处理 |
|---|---|
| doctor找不到Godot | 检查GODOT_BIN指向实际可执行文件，新设置后重启终端；对照安装版本，不改断言或引擎要求凑绿 |
| 新class_name未识别 | 先导入并读首个解析错误；涉及资源/场景按项目验证规则实机打开 |
| Godot AI连接失败 | 先核对打开的项目、插件/后端版本、dock和原始启动首错；官方Configure后按提示重启客户端，不猜端口；已知uv/attach排查见[实装记录](setup.md) |
| Python/磁盘/内存异常 | 先核实进程命令、归属与实时指标，不凭名字停止他人进程；必要的性能样本有时间和内存上限，见[执行计划](../../archive/specifications/world_engine_execution.md) |
| 需要新依赖/升级 | 核验用途、许可、固定版本及与当前引擎的兼容，保留回退；比较和官方来源见[维护](maintenance.md) |

纯文档工作只检查文档结构/链接与差异；不要把上述全部命令变成每次任务的强制启动脚本。
