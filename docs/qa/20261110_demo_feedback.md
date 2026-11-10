# Demo反馈修复与缓行诊断

2026-11-10。按用户要求先整合前阶段历史，再在`codex/demo-playtest-fixes`分开提交简单修复与开发诊断。main集成点`7def7d2f40e3584dfe6c455b6280d894a455a9e3`的CI42751032965已核completed/success；前阶段最终代码0856eff的CI42750266714也为success。没有把本包混入上述集成或改结算参数。

## 简单修复

`87262ffe5216da2d88afe4a2e8ba87ec20dfa1db`：人身默认持续跟随，按一次F恢复跟随，方向键/中键拖动解除；预置值事房按各格探索状态画墙门，不再以未探索的室内中心格跳过整个房间；中心/门未知时不提前显示房名、室内和门框。空间、遮挡规则、原房间状态及存档版本不变。连续坐标迷雾尚未实现，仍属于后续呈现改动。

doctor与import通过；`demo-simple-fixes-directed-timings.jsonl`三组74检查及`demo-simple-fixes-visibility-timings.jsonl`一组38检查退出0。后者覆盖原开局遮挡、三种人生和探索记忆；不是完整回归。一份有界原生探针通过普通Main人身验证一次F之后继续跟随、自由平移及恢复、墙格可见而中心仍未探索、真实绘制缓存包含房间。`demo-simple-fixes-native-final-20261110-114649.log`退出0，JSON failures为空；`logs/demo-simple-fixes-native.png`已实际查看，眼前外墙可见、室内仍黑。首轮临时探针过早静态加载运行类导致GameClock编译错误，修正探针加载时机后复验，不计作游戏通过。

一次Sol/custom原生静态审查无可确认可操作发现，日志`demo-simple-fixes-review.log`；审查没有启动游戏/测试。该SHA的CI **42751769110**在诊断修复提交检查点已核completed/success，完整CI通过。

## 独立开发诊断

`fff597619bcd89ced71eb186543e4effd116c8fa`仅增加`tools/diagnose_demo.py`、`tools/qa/demo_diagnostics.gd`和`tools/diagnostics/demo_recorder.gd`及工具用法。普通Main不加载；只有显式诊断入口包装原时钟executor及原结算Callable，按原参数调用并原样返回。内核被读档替换后重挂，停止记录时还原原回调。不散布临时print、不注入负载、不改变时间/预算/规则或写档。

入口为`python tools/diagnose_demo.py --seconds 120`，启动新试玩进程，默认采样后继续玩；关闭也会落盘。结果为`logs/demo-profile-*.json`与同名JSONL，每秒flush一条，时长1–300秒、最多20000帧样本/24个最大帧。细节和测量限制见[工具用法](../engineering/tooling/usage.md#配置和观察)。调用包装器有测量开销；原生画面/显示等待、调度及运行层剩余耗时不冒充GPU或某模块的独立成本。

验证：Python编译通过，非法0秒非零退出；headless 3秒/2秒采样、原生20秒均按时结束、输出可解析JSON/JSONL。`demo-recorder-contract-20261110-115411.log`退出0、failures为空：同一QA存档250ms推进，包装前后及读档更换内核后整个world/clock/motion未来hash均为`3264e4da0c4989377516ea692724816d8bb01ed61dd7f786f0f4015c6ab62c35`，结束时原executor及每个原step均恢复。使用独立QA slot并清理，不改用户普通档。首轮关闭处理误设Window属性后已按Godot4.7官方SceneTree API修正；最终smoke退出0。

原生报告`demo-profile-20261110-115542-28856.json`：Godot4.7.2/D3D12/RTX5060Ti，20.016秒采样、19.967秒正常运行，推进16550ms，约0.829×；最低load_rate0.269，帧间隔P95 17.650ms、最大48.840ms，时钟调用P95 8.627ms。累计callback较高为`consider:clothing`388.386ms、`previous:environment_fields`213.788ms、`field_opportunities`167.232ms和`consider_reading`141.949ms；不是仅凭名字认定最终根因。后段每现实秒约推进1000ms，地块加载已空，说明该开局样本包含降速恢复过程。未复现用户所有移动/交互负载，未据此优化算法或扩大预算。

诊断包一次Sol/custom静态主审，宿主命令故障后接续同一会话`01a1c39c-9879-7d40-bc24-a4c57dee682e`，提供准确SHA差异和源码完成；日志`demo-diagnostics-review-resumed.log`。确认一项P2：等候快进被排除正常流速比值时也错误漏计时钟CPU，内部步骤仍计时。先用10帧反例复现clock=0/executor=130730µs，再将CPU取样条件与正常流速筛选分开，保留等候完成帧；修复后clock=122070/executor=121849µs、正常流速运行时间仍为0。日志`demo-recorder-wait-red-20261110-120546.log`和`demo-recorder-wait-green-20261110-120612.log`。

最终工具代码`aa4f1a1fb893ed908281deda81fc2696659b3ea6`；同未来/回调还原合同再次通过（`demo-recorder-contract-final-20261110-120639.log`），最终2秒原生采样也退出0（`demo-profile-20261110-120705-29116.json`，生成时尚未提交所以revision仍fff5976/dirty=true）。最终代码CI **42753794423**在本次文档提交检查点精确登记为pending；前版工具CI42752959149先前观测in_progress，不继承为最终通过，不等待/轮询。工具包不重复完整本机游戏回归，简单修复的完整CI另见上文。

本工具独立于永久游戏回归，未额外注册全Main慢组。原生显示与规则同未来各有范围，不互相替代。

## 严重缓行修复

用户随后反馈严重缓行，本包在`codex/demo-slowdown-fix`处理，承接5526944而未自动合main。原诊断代码aa4f1a1的CI42753794423在本次真实提交检查点核为completed/success。

实际试玩报告`logs/demo-profile-20261110-121042-28184.json`：96.800秒采样，95.516秒运行推进77200ms，实际0.808×；最低准入倍率0.093，缓行49.536秒，帧P95 18.547ms/最大135.395ms，时钟最大97.893ms。`previous:environment_fields`单次96.783ms，且clock总CPU16.266秒中约8.248秒在executor之外。该报告包含用户自己的操作，不能与后续无人输入样本混作严格同路径对照。

定位与修复均归原owner，没有新增模拟循环或更改6ms预算、规则频率、因果顺序及存档格式：

- `WorldContinuityRuntime`统一发布所管理的canvas。普通时钟观察者只合并刷新请求，最后一个完整发布入口同步捕获一次；暂停、可见性及读档仍立即捕获，不按同一毫秒去重。植物视图在一次捕获内复用owner和视野上下文，保留原局部29×29查询及遮挡。
- `SimWorldEnvironmentFields.settle_budgeted`复用原目标批处理的handle，按16格工作项续算。通过内核本次resume的截止条件在工作项间让步，原设备消耗、来源切换和后续健康等阶段保持原顺序；无宿主截止条件沿相同过程结清。
- `ReolSimulationPacing`用250ms游戏时间尺度的累计工作/累计时长估算成本。原先取片段比值峰值，1ms因果切分会把普通固定成本放大成持续过载；新反例先失败后通过。仍计入未发布工作的CPU、保留所有已受理时间，并限制恢复斜率。
- 衣着只对当前有资格决策且无值守的主体计算环境选择，复用一次选择结果；原`wants_decision`查询及穿脱规则保留。

同一headless普通Main/人身、100×50ms显式推进探针，保留原listener顺序、参数和flags后还原：CPU从3179.445ms降到最终2281.599ms，约减少28%；自然视图普通listener累计从420.058ms降到0.606ms，最终统一捕获仍同步执行。日志为`demo-signal-profile-final-20261110-121523.log`、`demo-signal-profile-coalesced-20261110-121918.log`和`demo-signal-profile-fixed-20261110-123220.log`；数值不代表GPU性能。一次性探针只在忽略的logs，不进普通游戏或永久回归。

Godot4.7.2/D3D12/RTX5060Ti普通Main自动选择人身、不输入的90秒采样，均经过游戏60秒环境边界：

| 样本 | 实际流速 | 缓行时间 | 时钟最大 | 帧P95/最大 |
|---|---|---|---|---|
| 仅合并显示刷新，121949-17352 | 0.935× | 12.458秒 | 97.303ms | 14.647/105.308ms |
| 本包全部修复，122946-5212 | 0.986× | 4.764秒 | 17.645ms | 14.057/47.782ms |

完整JSON/JSONL为`logs/demo-profile-20261110-<样本>.json`及同名JSONL，最终没有world_errors。最终较低倍率位于前3秒地块加载及60秒环境刷新附近，之后恢复1×；环境callback最大仍有14.293ms，不能宣称6ms硬实时。另30秒原生真实Input移动经过39个格子，实际0.968×、后10个每秒采样倍率均1×，帧P95 16.105ms、时钟最大17.733ms，无world_errors。`demo-slowdown-movement-20261110-123143.log`退出0，`logs/demo-profile-movement-final.json`及`logs/demo-slowdown-movement.png`已核对；截图人身、地面和迷雾正常。连续坐标迷雾仍未实现，未宣称密集世界或用户全部操作完全复现。

doctor沿本轮最初检查通过，结构/文档链接、`git diff --check`及本机Sol/custom审查配置核对通过。定向运行：`test-20261110-122501.log`五组344检查，保护完整发布、pending旧画面、暂停同毫秒更新、原开局遮挡及工作场所；`test-20261110-122800.log`四组426检查，保护环境/衣着、分段响应与后续字段完全一致、内核域内截止条件；`test-20261110-122706.log`的短片段误缓行反例失败，修复后`test-20261110-122722.log`一组20检查通过，包含治疗/攻击不同预算同未来。以上最终验证均由Python包装器检查退出码及日志错误门禁，不等于完整回归。

主体提交`081b56ce0119c602d0a05985cd335c67e54d3f11`完成一次Sol/custom原生主审。宿主命令仍报`registered Core launch requires an installed app`，在同一会话`01a1c3bd-2195-7081-b187-a6a694f8b1c7`提供准确diff及相关源码，继续只读静态核查后退出；日志`demo-slowdown-review.log`和`demo-slowdown-review-resumed.log`。确认一项P2：灵体模式的提前返回跳过了读档新世界的flora覆盖回调重绑，保留旧植物owner。已将灵体判断移到绑定之后，只跳过绘制。复用三种人生的现有Main fixture增加灵体实际save/load反例，`test-20261110-124207.log`准确失败于旧owner，修复后`test-20261110-124249.log`一组42检查退出0，无额外全Main组。人身性能采样的行为路径不受此三行修复影响。

最终生产/测试`b364870e5ddc92f3c3de2d689fcf3e2755e8d67d`已推送，本次真实文档提交点一次发现同SHA CI42757726701为in_progress，完整CI待验；后续按HANDOFF的准确run/SHA核对，不开等待循环。尚有加载、来源候选和房间/拓扑等同步原子工作，不扩大为本轮全域性能重构。

## FPS显示与呈现频率核对

用户随后要求查看原生帧率，并质疑小场景性能余量。`GameHUD`顶部新增常显读数：Godot原生FPS、宿主画面帧间隔及当前2秒窗口最大间隔、世界有效流速/暂停/等候。沿既有0.5秒Timer刷新文字，逐帧只记固定标量；FPS仍按引擎1秒更新。F3完整诊断保留，并压回五行，避免底行被生活面板遮住。无模拟、存档、帧率上限或VSync改动，不另建Profiler。

doctor与`test_environment_runtime`一组17检查通过，日志`test-20261110-125037.log`。实际Godot4.7.2/D3D12/RTX5060Ti普通Main人身探针：默认常显、真实F3键切换、1280×720两块面板间284×57布局及F3不覆盖生活面板均通过。暂停1.2秒后FPS采样仍继续，整个world字典及共同毫秒保持不变。最终`demo-fps-readout-final-20261110-125342.log`退出0、failures为空，`logs/demo-fps-readout.png`已实看；探针只在logs，没有新增永久Main组。报告中的暂停后112ms窗口峰值包含探针自身序列化整世界的检查成本，不能当作普通游戏卡顿测量。

另以同一探针连续按住移动3秒，302次渲染采样中300次处于移动状态，但人物位置仅变化60次；原生FPS读取109，截图随后116。源码`PlayerCharacter._project_motion()`直接把原身体位置投影到Node，普通共同时间步为50ms，缺少玩家位移的连续显示插值；因此高FPS和1×流速仍可表现为约20Hz的位移。此证据不证明百级NPC吞吐，也未在本包改变移动规则或补插值。计划的共同运行/行动呈现出口已明确分别验收流畅、吞吐和规模，后续按该出口处理，不把主动缓行当性能验收通过。

准备本包实际提交时已核旧生产b364870的CI42757726701，结果仍为in_progress，未继承绿色。FPS最终代码`ac3dca32ffd8b3e6b7eda47c4efb756c8941e473`已推送；原生会话`01a1c3d0-baff-7801-b6f0-12057b2d7ba6`完成一次Sol/custom静态主审，无可操作发现，日志`demo-fps-review.log`；没有重复启动引擎或测试。完整CI状态见HANDOFF/BASELINE。

FPS收尾文档真实提交点：旧生产b364870的CI42757726701已核completed/success；当前FPS代码ac3dca3对应CI42759378487一次登记为in_progress，不能继承旧版绿色。完整CI待验，后续按HANDOFF的准确run/SHA核查。
