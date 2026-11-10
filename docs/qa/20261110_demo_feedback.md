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
