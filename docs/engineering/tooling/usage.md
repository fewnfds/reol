# 工具入口

类型：命令参考。采用版本见[BASELINE](../../status/baseline.md)，配置见[setup](setup.md)，验证强度和CI状态只查[开发循环](../workflow/testing.md)。

## 常用命令

```powershell
python tools/godot.py doctor
python tools/godot.py import
python tools/godot.py test
python tools/godot.py test --suite actor_batch
python tools/godot.py run
python tools/godot.py editor
```

`test`使用当前短smoke入口，不自动导入。`--suite NAME`可选`settlement`、`actor_batch`、`inventory`或`spatial`；完整短smoke还包含输入与呈现检查。`--timeout SECONDS`默认15、可选1–30秒。新检出、新class或资源不可识别时才需要import。`check`及旧`--shard/--jobs/--test-timeout/--timing-report`参数已移除，不保留指向旧体系的别名。日志实时合流落盘，错误和超时返回非零；普通run/editor不会因错误行强关用户窗口。

## 实际性能

```powershell
python tools/stress_demo.py --residents 150 --seconds 20 --quit-after-capture
python tools/stress_demo.py --release --residents 150 --seconds 20 --quit-after-capture
python tools/stress_demo.py --release --mixed --residents 150 --seconds 45 --quit-after-capture
python tools/diagnose_demo.py --seconds 30 --auto-start --quit-after-capture
```

压力入口两地各150人，持续使用普通Main原人物、寻路、生活、环境及共同时间；临时人口状态不写玩家档。`--actor-workers 0`与默认4可对照同一Packed数学的串行/线程执行，不能预设后者更快。普通诊断保留原开局；不加`--quit-after-capture`可继续试玩。

`--mixed`在两地巡行中加入实际取货/交付、原配方完工、可穿行门、有限交锋和携发光器物的移动视野。工地和配方通过原命令及共同时间准备，门不再周期性执行开关动作；`assembly_ms`和`crowd.mixed.setup_world_ms`与采样分开。采样报告记录实际完成的行为、世界流速、超16.67ms帧数和场景驱动耗时；如因缓行未覆盖完整负载，报告保留，进程返回非零。世界错误立即结束采样并保存第一手上下文。

Windows的`--release`先用`Windows Performance`预设导出当前代码到忽略的`logs/release-stress/`，然后启动真正的release exe/PCK，复用同一压力会话。需安装与当前引擎完全匹配的Windows x86_64 release模板；本机模板不入库。导出上限45秒，退出式采样进程上限为采样时长加45秒；不会启动CI或smoke。`performance_stress`特征只替换这个预设的启动场景，普通Main入口不变。

报告用`debug_build/editor_build`区分开发版与release，release还记录exe与PCK合并内容的`artifact_sha256`；源码`revision/dirty`按导出前真实Git状态记录。采样报告使用绝对logs路径，直接运行导出入口的默认诊断输出在`user://diagnostics/`，不向只读`res://`或普通玩家存档写入。开发版/发布版差异包括编译及运行形态，不能包装成算法提速；性能结论优先使用同构建类型的对照。

压力入口在最终观察位置最多等待15秒地形呈现完成后开始持续运行计时；`terrain_warmup_ms/terrain_warmup_complete`单独记录这段时间。初始化和运行中继续发生的加载仍需各自优化，预热后的样本不能冒充从点击开局起的全程结果。

结果在忽略的`logs/crowd-*`或`logs/demo-profile-*` JSON及JSONL。记录实际世界流速、帧时、结算步骤、批计算准备/采用等；测量本身有开销，单次差异不足以证明收益。先读已测最大成本，保持内容、人数、命令和采样窗口可比。headless只证明CPU/工具路径，画面性能用真实显卡渲染。

默认仅保留帧/区间计时；追加`--profile-kernel`才包裹每个结算步骤，供定位使用。报告明确写`kernel_timing_enabled`；关闭时未测的步骤/残差为null，不能当作零成本。比较吞吐时保持计时模式一致。

`--profile-navigation`可选统计原生/服务导航提供者的调用成本，最多保留4096组请求坐标作批处理探针输入；包含原路径缓存命中，不包括`SimConflictSpace`绕过提供者的直接搜索。该模式有额外计时与记录开销，不是普通试玩默认设置。`navigation_profile`只覆盖运行采样窗口；`actor_execution`明确为包含装配的累计计数，`actor_execution_capture`给出同一世界内运行窗口的差值。加载替换世界后后者为空，`actor_execution_capture_available=false`；历史累计线程ID也不代表运行期同时并行数。

`spatial_execution_capture`记录运行窗口的身体捕获/查询成本、候选段数及并行批次数；`geometry_read_capture`记录新增读取页、局部更新格与捕获页引用。均在同一世界内作差，替换世界后为空；没有满足批量阈值时并行数为0，不能用探针的局部倍数冒充普通游戏收益。

`--pacing-policy full-rate`只在临时压力场景绕过主动限速，保留有限准入、正常执行预算、续算和规则；只用于判别准入政策与实际吞吐，不是游戏设置。报告记录policy和`max_fps`，区分executor调用/无公共推进、完整世界边界、公共发布及其跨度；逐步骤同时记录calls与logical_boundaries，不能把续算次数当作新的逻辑tick。完整世界边界计数来自原世界统计，采样结束未完成的边界可能已进入某一步。

`--profile-render`启用Godot原生viewport CPU/GPU绘制计时及全局CPU准备计时，记录`render_timing_enabled`和各自分位数。它们是最近可用渲染帧的数据，不包含脚本/物理、也不能与当前帧时相加；诊断开销单独对待。headless没有有效GPU绘制计时。

运行实现位于`scripts/diagnostics/`，压力场景为`scenes/diagnostics/crowd_stress.tscn`；`tools/qa/`只保留CLI适配入口，避免被`tools/.gdignore`排除出release包。普通Main不加载诊断器。HUD常显FPS、帧间隔和世界流速，F3展开详情。Godot编辑器Debugger → Profiler/Visual Profiler用于继续定位；宿主帧间隔不能冒称GPU时间。

## 其他工具

- `python tests/tool_smoke.py`：几秒内核对启动器的错误/超时退出，仅在修改启动器时需要。
- `python tools/check_structure.py --audit-code`：可选的链接/字面路径及源码引用图检查，提示UID、重复类、反向呈现依赖与无静态入口的文件；动态调用需人工确认，不自动删代码，不是提交门禁。
- `python tools/setup_codex.py --check`：配置发生问题时核对项目条目，不证明MCP握手；不必每包执行。
- Godot AI负责实时场景/输入/截图，使用官方dock Configure生成认证attach，操作前确认项目与实际会话。Context7查目标版本API；不手改第三方addon或用裸HTTP绕过连接。

手动review使用已有项目路由/配置，策略见开发循环。Windows性能导出已实际运行；它是无普通存档写入的临时人口诊断包，不等于正式游戏发行或目标PC验收。
