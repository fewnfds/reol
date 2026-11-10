# 超凡者优先U0：公共接缝整理验收

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

日期：2026-11-03。用户要求修仙世界重心回到超凡者能力、冒险和组织，普通生产先维持循环；随后恢复完整游戏Goal active。本包完成计划调整与现有公共接缝整理，不新增战斗/任务/远区事件引擎，不迁档，不制作新美术。最新数字与当前限制统一见[BASELINE](../../status/baseline.md)。

## 变更

- [实施顺序](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/transcendent_focus.md)：U0公共基础→U1超凡冲突→U2功法/器物构筑→U3冒险/任务→U4组织/权力→U5首小时/规模。P/F为领域验收索引，生产/建筑不再作为必须全部做完的前置；浅沟、导流和精细农务暂缓。
- [参考研究](../../../design/research/transcendent_focus_sources.md)：国产修仙、战略/战棋、人生模拟和远区分精度的一手资料，说明设计宣称与实际版本记录的区别。
- `RegionalSimulation.owns_for_scope`把原八种用途的活动集合放在一个固定目录，保留原对练阶段差别与runtime回调范围；`body_action_owns`可排除自身。主体控制权、原生`actor.active`及施工/休息职责仍分别判断，没有第二份锁或任务真值。
- `activity_previous_autonomy`统一投影原活动的返回自主标记；本人当前自主、寄魂差事等仍由身份校验单独处理。
- 保存/形状检查共享`SNAPSHOT_DOMAINS`，必要边界查询共享`BOUNDARY_DOMAINS`；原执行顺序拆为有名阶段，没有排序广播或同刻换序。
- 十八个原领域增加只重绑引用的`bind_world`，候选全通过才提交；原器物/灵源已有绑定行为仍保留。没有调用initialize重置进行中的过程。
- `SnapshotValues`承接无状态JSON值规范与数值形状工具，VillageRuntime保留兼容包装；联合快照使用显式上下文/校验接口，不再直接访问runtime私有玩家/内容/迷雾字段。

## 定向与完整回归

定向日志：`logs/activity-ownership-probe-20261103.log`与`logs/snapshot-boundary-probe-20261103.log`均最终完成/零失败。覆盖真实灵源竞争/排除自己、对练阶段、取消、独立候选恢复后的域绑定、未知主体/用途、丢域失败原子性、JSON小数/最大整数/StringName转换、不支持值留给运输层拒绝、双份home不一致拒绝、单村落/双聚落在途/地图候选及真实v34。

最终`python -u tools/godot.py check`退出0、CHECK PASSED；完整导入/规则/runtime/全图旧算法/历史存读均通过。原始日志：

- `logs/check-structure-20261103-215207.log`
- `logs/check-import-20261103-215207.log`
- `logs/check-test-20261103-215216.log`

实际检索最终导入与测试日志，无`SCRIPT ERROR`、`ERROR:`、`WARNING:`或`FAIL`。独立只读代码复核对照八种用途集合、候选组合限制、数值规范、阶段与绑定行为，未发现本包新增语义问题；这不是未来所有组合都已证明的保证。

文档落稳后`python tools/check_structure.py`退出0、无错误，`git -c core.safecrlf=false diff --check`退出0；资源严格检查`python .agents/skills/godot-nodes-scenes/scripts/check_godot_project.py . --strict`退出0、无错误/警告。未全库规范换行、未修改addons。

## 两次完整游戏进程接续

run186/187均从新游戏进程，经原loader读取真实`tests/fixtures/session_v34.json`，完成原引息→取石/温养/释热→存石→释热→实际行旅河湾，到7200000ms。未注入坐标、权限、NPC策略或额外资源。时间通过共同GameClock推进；这是可复现运行验证，不冒充正常速度首小时试玩。

临时`logs/u0_live_replay.gd`由现有受扫描`tests/runtime/helpers/spirit_source_replay.gd`生成，仅替换两处证据输出路径前缀，避免覆盖旧证据；业务动作保持一致。新`logs/u0_cleanup_future_a.json`和`_b.json`全联合169934 UTF-8字节一致，**也与U0前`logs/world_map_live_future_a.json`逐字节一致**，SHA256为`46c56b391dae102e8df3164292a7361ab6f1a7366ddc6e3131064664d5319694`；两候选均有效，qi16/charge11。过程报告为`logs/u0_cleanup_restart_a.json`/`_b.json`，比较依据为`logs/u0_cleanup_manifest.json`。

v34原180474字节、SHA256 `07e4a64c2e8415afd912220b3c017bd269947c52c0a23d1536b0888d9f090c78`未变。全部真实旧fixture、普通用户存档保留；根/区域版本不变，冻结迁移链不重写。

run187首次eval在helper刚注册时返回`EVAL_GAME_NOT_READY`，该次未执行回放；复查同run仍live后重试成功，没有重启另一个进程冒充原进程结果。原生1280×720图`logs/u0_cleanup_runtime.png`已查看：河湾人物、地形、HUD和中文面板正常，F居中，游戏7200000ms暂停。当前run游戏日志仅helper注册信息、无错误/警告；编辑器游标13后无新增条目。旧WASAPI/间歇呈现问题仍未全结案，本包未改用户设备。

## 本包没有解决的其他范围

完整战斗/修炼/装备/任务/组织和事件化远区仍需U1–U5实现；本包不是完成游戏。完整活动生命周期尚未抽象；目前只消除重复的占用查询和机械接线。迁移链拆分、去掉存档兼容副本、长期历史摘要/回收以及规模性能各需独立包；不能用本次等价重构宣称它们达标，也不以简单删除历史改善指标。

正式资源、全动作、人物CPU/纹理规模预算与声音等限制保留，当前状态看BASELINE。完整游戏Goal保持active，下一玩法包按超凡者主线，不再续做集雨沟。
