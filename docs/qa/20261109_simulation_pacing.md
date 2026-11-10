# 共同时间过载降速验收

日期：2026-11-09。产品及永久测试提交`f4257e38a1665c08c8596028fe71c0cea0dbeab9`基于main `2c4ea10723d8140c5ae4b5f4c599f156d2ea6e5b`，开发分支`codex/adaptive-world-time`；准确受检代码、完整回归、审查和集成终态在[BASELINE](../status/baseline.md)登记。本页记录本包实际样本，不替代全项目密集规模/16GB整机验收。合同见[运行流速](../engineering/simulation-pacing.md)，出口沿[原主计划](../plans/foundation-priorities.md)。

## 代码与反例

共同整数毫秒、原事件顺序、根53/区域44及七字段时钟快照保持。`ReolSimulationPacing`只调节未来时间准入，已有欠算和显式目标不截断；真实宿主计时、6ms合作式预算、显示推进及普通HUD/F3已接入。

新增永久owner为`test_simulation_pacing`：最小合法时钟/过程fixture验证有限准入、恢复斜率、宿主状态不入档，以及治疗990/1000/1010ms和攻击1000ms在不同负载/预算下相同未来。简化HP不是新药物玩法。内核owner补宿主让出反例；实际世界owner补截止时刻已过且世界pending时不投影半身体。原测试显式模拟帧改用`advance_frame`，不继续伪造引擎回调；旧无限实时追赶断言按新政策改写，已准入旧欠算仍验证完整处理。

本机Godot4.7.2最终定向8组：`test_clock_scheduling`、`test_clock_world_commit`、`test_conflict_runtime`、`test_private_exchange_runtime`、`test_settlement_kernel`、`test_simulation_pacing`、`test_thermal_devices`、`test_village_simulation`，**796检查/0失败**，包装器退出0。日志`logs/test-20261109-084627.log`、计时`logs/test-timings-1794185187747567100.jsonl`。首轮4组265检查通过；一次误用未注册suite参数在执行前退出1，不是产品失败或完整覆盖证据。

对应产品/永久测试SHA的[CI42542611182](https://github.com/fewnfds/reol/actions/runs/42542611182)已在真实提交检查点核completed/success，12片及完整覆盖聚合通过；本包采用该完整CI，不重复本机全游戏回归。其后现有原生QA工具两处手动续算也改用`advance_frame(0.0)`，不改变产品或永久测试。一次主代理调用的`codex -c model='"gpt-6.1-sol"' review --commit f4257e38a1665c08c8596028fe71c0cea0dbeab9`已完成，custom路由、退出0，无可确认修复问题；审查未启动引擎/测试。日志`logs/simulation-pacing-native-review.txt`。部分只读命令曾遇宿主Core启动错误，其后恢复文件读取并完成审查；未改变模型或权限。

## 原生Main与人工负载

[simulation_pacing_probe](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/simulation_pacing_probe.gd)使用普通Main和人身开局，不加载或覆盖玩家存档；真实D3D12/Forward+，NVIDIA GeForce RTX5060Ti，1280×720，限制显示60FPS。在16个原结算步骤各增加2500µs忙工作，保留原callback/模式/业务结果，之后移除。它是控制机制样本，不是密集人口性能模拟。

| 阶段 | 现实秒/帧数 | 游戏毫秒 | 实际平均速度 | 帧间隔P95/最大ms | 结束准入倍率 |
|---|---|---|---|---|---|
| 开局后普通段 | 4.005/239 | 2050 | 0.512× | 19.619/43.267 | 0.715× |
| 人工负载 | 8.014/480 | 1300 | 0.162× | 17.600/21.138 | 0.171× |
| 移除负载后恢复 | 12.016/723 | 9950 | 0.828× | 16.704/16.888 | 1.000× |

普通段包含开局成本和调速恢复，不能当稳态1×基准；不同阶段也不能推导人工负载提升FPS。负载段已准入欠算最大249.001ms，普通段250ms，未无界增长；时钟调用P95为7.797ms，最大8.523ms。普通段原子调用峰值35.542ms超过6ms，直接证明合作式预算仍非硬上限。记录268次公共时间发布，均只暴露完整世界。

原始报告`logs/simulation-pacing-native.json`，进程日志`logs/simulation-pacing-native-run.log`；已查看`logs/simulation-pacing-loaded.png`，普通HUD保留1×按钮并显示缓行，F3显示欠算和成本，世界只显示已提交状态。已查看移位后的`logs/simulation-pacing-resumed.png`，诊断不遮挡历法行；运行界面不是美术定稿。

## 存读与完整停开

探针使用独立`user://tests/simulation_pacing_native.json`，先结清已受理时间并暂停，保存当前完整会话。随后250ms世界/时钟/身体未来归一化SHA256为`c17c2f4da3db54e0f56a57c6329b6930dc79146aee24604c2bf56c5a653bf93c`；同进程载入后未来一致。第一进程完全退出后，独立`--resume`进程读取相同档并推进250ms，hash再次一致，负载倍率重新建立为1。两个进程均退出0、无SCRIPT ERROR/ERROR；恢复日志`logs/simulation-pacing-native-resume.log`。

## 复查与限制

现有`settlement_kernel_acceptance.gd`两处零时间续算迁入`advance_frame(0.0)`后，独立smoke在真实Main装配下以工作预算1保留/完成25ms显式请求，最终世界/公共时钟均25ms且无pending，退出0；日志`logs/pacing-acceptance-driver-smoke.log`。这两处QA改动及后续Markdown不改变已通过完整CI的产品/永久测试；最终推送的后续SHA CI仍须独立登记。

运行命令为`Godot --path . --script res://tools/qa/simulation_pacing_probe.gd`，随后同命令加`-- --resume`。探针内部70秒单调/实时timer门禁，外层须保留80秒进程超时。初次直接类型引用runtime导致入口在Autoload建立前编译失败，已按既有原生探针方式延迟加载；失败日志不算运行验收。

本轮没有升级引擎、GPU、权限或插件；没有可调用的Godot AI实时工具，沿项目CLI进行原生运行、截图及独立进程验证。RTX5060Ti样本不证明RTX3060或16GB整机目标。单个不可抢占步骤、同步文件操作、GPU阻塞和极端规模仍能造成长帧；暂停期间不推进，后台长停顿有限准入，不提供离线结算。
