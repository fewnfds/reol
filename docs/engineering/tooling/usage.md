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
python tools/stress_demo.py --release --complex --residents 1000 --rooms 48 --sources 128 --seconds 15 --profile-cpu --input-probe --quit-after-capture
python tools/stress_report.py logs/<capture>.json
python tools/diagnose_demo.py --seconds 30 --auto-start --quit-after-capture
```

人数是每地6–4096，实际总人数为两倍；持续使用普通Main原人物、寻路、生活、环境及共同时间，临时状态不写玩家档。`--actor-workers -1`按硬件/任务量选择，`0`串行，`1..64`指定本批并发上限；实际按逻辑处理器及chunk数收窄，`--simulation-thread off`关闭协调线程但仍运行同一runner。`--actor-projection ordered`保留逐人采用供同包对照，默认partitioned只对证明独立的身体分区写入；`--actor-minimum N`实验人物候选最小集合，默认64，小集合保留直接入口。`--release-binary PATH`复用同一exe/PCK进行规模/并发/后端对照，不能预设线程越多越快。不加`--quit-after-capture`可继续试玩。

`--complex`临时装配1–64个5×5房间、5–512个实际冷热/五行来源；约四分之一来源由原人物携带，其余通过原实物命令移动。两地运行单位一起布置在观察者附近，不使用假移动。场景结构是一次性安装、没有历史施工回执，不可当作正常存档fixture。

`--profile-cpu`用Windows线程CPU时钟、进程内存及整机可用内存每0.5秒侧录到`.cpu.json`；记录涵盖装配，`stress_report.py`按capture时间范围加权裁剪边缘样本，CPU秒才是真实执行，GDScript微秒仍是经过时间。`--gpu-index N`固定适配器序号，须核对报告renderer名称；两张卡的序号未必长期相同。CPU竞争、整机内存不足及其他程序占满GPU的窗口只保留为干扰证据，不用于选择最优线程数。`--input-probe`只测宿主请求等到完整世界交接的延迟，不是鼠标到显示像素延迟。身体、来源响应与后台等待的成本可在同一JSON查看。

`--mixed`在两地巡行中加入实际取货/交付、原配方完工、可穿行门、有限交锋和携发光器物的移动视野。工地和配方通过原命令及共同时间准备，门不再周期性执行开关动作；`assembly_ms`和`crowd.mixed.setup_world_ms`与采样分开。采样报告记录实际完成的行为、世界流速、超16.67ms帧数和场景驱动耗时；如因缓行未覆盖完整负载，报告保留，进程返回非零。世界错误立即结束采样并保存第一手上下文。

Windows的`--release`先用`Windows Performance`预设导出当前代码到忽略的`logs/release-stress/`，然后启动真正的release exe/PCK，复用同一压力会话。需安装与当前引擎完全匹配的Windows x86_64 release模板；本机模板不入库。导出上限45秒，退出式采样进程上限为采样时长加90秒；不会启动CI或smoke。`performance_stress`特征只替换这个预设的启动场景，普通Main入口不变。

压力导出还把Godot的实例shader参数缓冲提高到262144个槽，容纳8192身体的实际呈现，避免先撞到默认约4096实例的缓冲上限；普通游戏不覆盖此设置。导出同时写exe旁的`.build.json`记录源码版本、dirty和内容digest；复用时检查digest并读取原构建信息，缺失或不符时版本标为unknown，不冒用当前工作区HEAD。

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
