# 源场基础与密集基线

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

日期：2026-11-05。F0为隔离规则；普通Main尚未替换旧Q模型，F1/F2未验收。
合同见[环境规范](../../../design/proposals/environment.md)，实施见[执行页](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/world_engine_execution.md#新源场首包实施与验收)。

## 实现范围

- `SimEnvironmentFieldRules`：欧氏圆形线性核、百万分整数权重；五行/冷热七通道，同通道取max，冷热抵消后查等级温度表。
- `SimEnvironmentFieldIndex`：原物ID的可重建来源投影和空间桶；移走赢家后回查次强，返回旧/新范围，不保存原物数量、保管或储量。并未接真实掉落/堆叠。
- `SimEnvironmentFieldTide`：共同时间、seed和固定坐标决定98%–100%倍率；粗空间相位插值，单个三角波，不逐物设Timer。
- `SimEnvironmentFieldResponse`：已知常量/线性目标段的一阶响应、积分及严格候选恢复。这里只证明单段及组合夹具，不是完整气候/潮汐/温度表边界调度；该接续仍待做。

五组定向8110断言、0失败，无SCRIPT ERROR/ERROR，1.7005秒、工作集峰222416896B；30秒/1GiB外部owned-process限制。日志`logs/source-field-focus-final.json`。覆盖核/温度界限、潮汐周期与signed seed/坐标、最强移走/移动/同值稳定来源、小图参照、线性响应与JSON完整精度恢复。没有使用普通房间或真实搬运来冒称接入。

## 密集查询基线

入口`tests/benchmarks/environment_field_baseline.gd -- <size> <query_count>`；须由`tools/world_benchmark.py::run_guarded`施加30秒/1GiB限制。Godot4.7.2开发程序，Windows，i5-13600KF/20逻辑核/34104020992B物理内存。每格一条独立来源投影，半径4/8交错，七通道均非零；不创建真实物品、身体或Node。

| 地图/实际来源 | 初始化 | 1024点基础查询 | 每64查询批p95/p99 | 1024点潮汐 | 缓存值热/五行应用 | 工作集峰 |
|---|---|---|---|---|---|---|
| 64² / 4096 | 27.878ms | 323.878ms | 21.187/21.187ms | 5.460ms | 1.779ms | 102481920B |
| 512² / 262144 | 1833.448ms | 641.975ms | 42.513/42.513ms | 5.335ms | 1.872ms | 443617280B |

原始日志`logs/source-field-baseline-{64,512}.json`；512进程3.5589秒、采样私有峰435449856B，完整退出0。512点查实际检查1014016条候选；应用阶段重查准备641.048ms单独计量，未藏到1.872ms内。2621次原地强度更新约1%用39.514ms，只登记索引失效，不含实际全场重算、移动历史或室温。批p95不是帧p95/FPS；并非全地图每格重建。暂不继续用字典实现冲1024²/2048²，先优化真实瓶颈。

结论：来源桶内字典遍历明显慢于潮汐，应先用紧凑来源槽和有界脏块缓存。不能把1%来源变更当1%重算；分散变更可能使大多数块失效。长距离移动需分别处理旧/新邻域，避免它们的包围矩形误伤全图。缓存是可重建视图，未来环境响应必须先结旧目标到变更时刻，不能覆盖历史或新增时钟。

## 旧包观察面板审查修复

`661ddbd996ff2ea1e30e509b4816555ad2344b69`一次Sol/custom原生只读审查142.590秒、退出0，发现P2：面板挡住后续场景点击。新增“切换重叠器物”按钮，保存点击位置，每次按当前可见对象重算，不保留过期候选；隐藏对象不泄露，移动/删除可安全处理。

异步原生窗口`logs/inspector_cycle_native.gd`等待布局，再通过Viewport派发图标和按钮按下/释放，连续切换三次；世界完整快照不变。进程6.7301秒、工作集674447360B、采样私有峰999940096B，30秒/1GiB限制，退出0且无引擎错误；日志`logs/inspector-cycle-native.json`，截图`logs/inspector_cycle_gui.png`已观察。实际使用Forward+/RTX3060；历史设备记录不代表这次设备。携物位置是明确的呈现夹具，不冒称真实搬运。

最初同步测试强制Container排序后仍不能点击按钮，4失败；加鼠标motion亦失败。这是未等待真实布局的无效同步GUI假设，日志保留为`inspector-cycle-focus{,-with-motion}.json`。同步组现只测信号组件连接与候选规则，真实GUI由上述异步原生探针验证，不把emit_signal称为GUI输入覆盖。

修后同步weapon_items_runtime为105断言、0失败、7.2493秒/407805952B，无引擎错误，`logs/inspector-cycle-component-final.json`。可重复原生入口已保存在`tools/qa/object_inspection_cycle.gd`：6.3771秒、工作集696107008B、私有峰1034022912B、退出0，日志`logs/inspector-cycle-tracked-native-late-types.json`。独立SceneTree最初提前引用runtime类型导致autoload GameClock未注册，已改为初始化后动态取得Node；失败日志保留，最终无脚本错误。
