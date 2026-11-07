# 术语与运行入口整改

2026-11-07；分支`codex/sparse-world-execution`，起点`d27337d67c0148132dfaef2d802d72a860b62d38`，受检代码`771a587d20a38998845331fb214cd886d361d876`。包含上轮待提交的AGENTS、DOCUMENTATION、HANDOFF修改；没有覆盖其他工作。收尾提交仅登记文档证据，代码不变。

## 整改范围

现行design、engineering、specs、plans、status及入口文档按实际源码核对。统一规则见[术语与代码映射](../engineering/terminology.md)，当前说明直接描述对应对象；旧QA/archive、原fixture、第三方资料与历史ADR原文不重写。小说叙事里的“灵机”等感受用语保留，不宣称存在同名数值通道。

- 中文概念固定：五行、五行环境影响、静态五行亲和、灵气、器物充能、储热量、机构贡献分别指向原owner；不合并环境、储量和温度。
- 实际`qi`统一中文“灵气”；HUD和地块描述同步。`charge`、`stored_q`不改成灵气库存。
- 文档使用真实class名，包括`SimEntityQuery`、`SimStructureQuery`等；`GameClock`是autoload实例，类型为`ReolGameClock`。候选职责标签不冒充已有class。
- 原`RegionalSimulation.local_heat`改为唯一运行成员`environment_fields`，同步生命周期、器物、环境受体、建筑、光照、运行适配、反射访问及调度目录；恢复候选局部名为`next_fields`。
- 区域schema43、根schema52及JSON键`local_heat`保持。`SNAPSHOT_KEYS`在capture及shape validation明确映射，restore仍读相同存档键；没有新runtime兼容getter或平行owner。
- `ReolContentDB.local_heat`仍是热设备参数定义，旧存档字典字段和定义文件路径保留；历史独立模型不当作活RegionalSimulation改名。
- 现有测试/工具的活成员与fake world同步，不改原fixture。环境组检查存档仍有`local_heat`、没有运行成员名作保存键，并检查恢复后的独立owner。

## 验证证据

- doctor及Godot4.7.2 import通过：`logs/terminology-import.log`。导入仅带来shader `.import`末尾空行噪声，已恢复原内容，不入本包。
- 一次定向10组：**1203断言、0失败**，组内约67.81秒，240秒上限未触发；无SCRIPT ERROR/ERROR。日志`logs/terminology-directed.log`，计时`logs/terminology/directed.jsonl`。
- 组包含共同时间提交、建设拓扑fake、正负温度受体、局部光、稀疏来源与恢复、普通世界场、保存事务边界、普通存读及独立候选恢复。存档格式与进行中世界的检查沿现有owner，不增整套新测试。
- Godot AI当前返回PLUGIN_DISCONNECTED；没有改连接配置。使用同版本Godot CLI和临时捕获脚本运行真实Main，RTX3060/D3D12画面与Label文本核对“灵气20/20”，截图`logs/terminology/qi-hud.png`。该图为暂停开局界面及其选中人物HUD，不代表新玩法或性能验收。
- 临时捕获脚本首次从忽略目录直接引用GameClock未解析，保留`logs/terminology-hud-20261107-165449.log`；改为获取实际autoload实例后成功，最终日志`logs/terminology-hud-console-final.log`。未改产品代码绕过故障。
- 结构/本地链接、差异与当前class链接显示名核对通过。没有为了纯命名包重复本地完整回归；完整CI待准确受检SHA结果。

## CI与审查

本轮真实提交检查点一次查到[run42356120868](https://github.com/fewnfds/reol/actions/runs/42356120868)，完整headSha`d27337d67c0148132dfaef2d802d72a860b62d38`，当时in_progress，conclusion为空。按规则留待下个真实提交点，不轮询或等待。该run也不能证明本包改名通过。

受检代码由主代理一次`gpt-6.1-sol`/custom原生静态审查，终态无可执行发现；日志`logs/terminology/review-771a587.log`。审查核对当前调用、反射/调度和存档键，没有重复测试、启动引擎、CI或嵌套审查。推送不自动合并main，不把定向10组或旧SHA结果写成完整回归成功。
