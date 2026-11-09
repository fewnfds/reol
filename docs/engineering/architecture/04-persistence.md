# 当前代码架构与边界：存读提交边界

## 状态与职责

存档是**当前世界的数据快照**。共同时间、身体与实物、库存/账本、地图改造、环境响应及在途过程一起保存；原状态继续归各领域，不创建第二个对象库。底图按档内种子和生成描述重建，派生空间索引、显示Node及缓存重建；恢复不重放全部历史，也不从新开局补发物资或知识。

| 模块 | 职责 |
|---|---|
| [SimSaveStore](../../../scripts/persistence/save_store.gd) | FileAccess/JSON、临时文件验证、备份和替换；不认识人物、建筑或领域规则 |
| [SimSaveRegistry](../../../scripts/persistence/save_registry.gd) | 通用数据参与者登记，统一capture、候选stage、校验及install；纯数据，不扫描SceneTree |
| [SimWorldSaveDomains](../../../scripts/sim/world_save_domains.gd) | 当前世界的唯一存档领域目录；声明wire key、可信工厂、恢复适配、跨域校验、重绑及库存引用范围 |
| [SimSaveSession](../../../scripts/runtime/save_session.gd) | 通用会话操作：严格同步保存、普通保存请求/回执、独立候选加载与提交；通过明确回调适配宿主 |
| [WorldSessionSnapshot](../../../scripts/runtime/world_session_snapshot.gd) / [WorldRestoreFactory](../../../scripts/sim/world_restore_factory.gd) | 联合封套、内容/地图/区域候选及玩家投影的校验；[WorldContinuityRuntime](../../../scripts/runtime/world_continuity_runtime.gd)负责成功后的场景接续 |
| [SessionSaveSchema](../../../scripts/persistence/session_save_schema.gd) / [SnapshotValues](../../../scripts/persistence/snapshot_values.gd) | 当前根版本、形状及JSON值合同 |

区域共同状态（时间、路线、区域、运输等）由`RegionalSimulation`校验；各领域适配器检查其原实例、引用、成本和因果。纯登记不自动赋予新领域空间、行动或认识能力；这些仍沿[领域接入检查](05-framework-domains.md#新领域的接入检查)处理。

## 新字段与新领域如何接入

**已有领域增加字段：** 在原owner的`to_dict`、`restore`及其schema校验中维护该字段。通用管线、文件层和中央逐域循环均不改。无法由旧事实重建的新状态需要明确版本/拒绝边界；通用模块不猜业务迁移。

**新增领域：** 在`SimWorldSaveDomains.registry()`登记一次适配器。简单领域复用`_standard`，声明运行成员、原脚本和内容规则键；特殊初始化或校验提供Callable。持久记录由owner的非空`to_dict()`提供，wire key允许与运行成员不同，例如`environment_fields`保存为`local_heat`。可信Script来自项目目录，存档不能指定任意脚本执行。

登记顺序是明确的恢复依赖顺序。通用管线先构造所有候选owner，再执行可选`prepare`、按序恢复、最后执行全部跨域`check`。`prepare`用于环境等需要先提供候选接口、后恢复数据的情况；不能借它查询活世界。各适配器只修改独立候选，失败不能调用install。完整世界校验后，install先替换全部owner，再统一重绑，防止绑定看见新旧混合状态。库存引用贡献沿同一目录汇总；受保护的原物ID冲突拒绝，不能被其他贡献覆盖。

当前`RegionalSimulation.to_dict/restore`与shape检查均消费该目录，不另维护一份存档domain清单或逐域new/restore/bind链。普通新增领域仍须在世界装配处创建其新局实例，这是新局的职责；存档恢复不调用开局发行逻辑。新业务规则及跨域引用需要自己的验证，自动序列化不能替代它。

## 保存请求与安全边界

普通UI/F5使用`request_save(path)`：返回`OK`只表示受理，真正完成由`save_finished(path, result)`回执。`SimSaveSession`取得`GameClock`的宿主准入屏障，停止新增实时步、显式推进和等待请求；原暂停状态和玩家后续暂停操作保持。每次续算仍受6ms合作式预算及原领域工作预算约束。

只结清已经受理的当前区间和显式请求。未开始的`frame_debt_ms`及未来`wait_target_ms`已经可保存，不为存档跑完整段等待或旅行；显式目标尚无存档字段，必须完成。结清后同步捕获/写档，再释放屏障，从新的宿主采样点继续，保存耗时不变成追赶时间。30秒内未结清、结算FAILED或取消均给失败回执并释放屏障；这些写入前的失败不改主档/备份，也不删除在途请求。

`save_game(path)`保留严格同步合同：未到完整共同时间或正在发布时返回`ERR_BUSY`。加载经`SimSaveSession.load_now`读档、stage独立候选、完整校验后才调用采用回调；失败不改活世界，时钟回调内或保存等待期间拒绝重入。帧间合法加载可替换FAILED或部分世界，提供恢复途径。场景退出取消未完成请求并释放屏障。

文件阶段同步完成，不宣称后台无停顿。`SimSaveStore`核验临时文件，保留可用上一份后替换主档；编码/磁盘失败沿其Error返回，不把空快照当成功。若实际大档测量证明JSON是瓶颈，再评估Godot内置二进制/压缩；更换编码不减少领域恢复校验。

## 采用方案与成熟参考

采用Godot自带`FileAccess + JSON`和项目内薄通用模块，**不引入存读插件**。现有难点是领域装配与安全提交，文件编码层本身很小。这里借鉴声明式数据块/参与者模式，不复制外部项目实现。

| 一手来源 | 可借鉴及取舍 |
|---|---|
| [Godot Saving games](https://docs.godotengine.org/en/4.7/tutorials/io/saving_games.html)、[ResourceSaver](https://docs.godotengine.org/en/4.7/classes/class_resourcesaver.html) | 游戏声明需保存状态，内置能力编码。Resource适用于Resource数据组织，现有纯数据owner无需整体迁树 |
| [OpenTTD savegame format](https://github.com/OpenTTD/OpenTTD/blob/cd211f63489e386425bae282bb31384780099e68/docs/savegame_format.md) | 稳定文件流程、分块与各域handler/descriptor；借鉴职责分工，不复制GPL代码 |
| [SaveKit](https://github.com/fernforestgames/godot-savekit/tree/9ca2dabdfd24712a2ad60b76d0a04e5a981b6e4a)（MIT） | exported/storable属性及自定义codec可简化对象图；默认load修改活SceneTree并清理缺失Node。仍需适配独立候选、原owner和远区 |
| [I, Voyager Save](https://github.com/ivoyager/ivoyager_save/tree/06fe11f86dfab3a99669eae9fd52bf476b22742a)（Apache-2.0） | `PERSIST_PROPERTIES`声明Node/RefCounted属性；默认先销毁程序化活对象，独立候选builder在所读版本仍标experimental/untested，共享Array/Dictionary别名不保留，不直接适合当前模型 |
| [Save Made Easy](https://godotengine.org/asset-library/asset/2056)、[SaveSystem](https://godotengine.org/asset-library/asset/4832)（MIT） | 轻量键值读写，可简化小型场景；未提供本项目完整联合候选与跨域业务校验 |

上述源码在2026-11-09静态核查；没有安装或宣称完成插件4.7.2兼容验收。研究快照在本地`logs/save-architecture-audit-20261109/`，采用理由和公共接口以本页维护。

## 格式与支持范围

本次模块重构保持根53、区域44及现有领域wire记录，`local_heat`仍映射唯一`environment_fields`。目录变更不代表新格式；不强制把现有Dictionary改成Resource或转储所有对象。当前联合封套中的既有兼容投影也保持，不能借接口改造静默删字段。

当前内容包v2绑定39份定义；`local_actions.json`、`workplaces.json`、`sparring.json`仍有直接读盘路径，尚未完成全部会话规则闭包。这个缺口继续归[唯一主计划](../../plans/foundation-priorities.md)的规则绑定前置，不由新存档模块推测补造旧规则。当前只接受根53，详细版本边界见[兼容政策](../compatibility.md)。

必要验证包含最小参与者扩字段/扩域、坏候选原子拒绝、原领域roundtrip、预算续算与回执，以及普通Main完整退出重启后同checkpoint/同未来。具体版本、结果和限制查[BASELINE](../../status/baseline.md)。
