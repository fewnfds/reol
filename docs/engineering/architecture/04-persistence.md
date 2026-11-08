# 当前代码架构与边界：存读提交边界

## 存读提交边界

存档是**当前世界的数据快照**，不是从开局重演所有操作。统一时刻的时间、人物与物品、库存/账本、地图改造、环境实际状态及尚未完成的过程一起保存；进行中动作保存当前阶段与必要余量，读档后继续。日志/回执可能是领域当前数据的一部分，但恢复世界不依赖重放全部操作。

逻辑上保存整个世界进度，不等于转储全部内存：不可变底图按档内种子、版本和生成描述重建，地形改造另存；显示用 `Node`、围合/占地索引和可重建缓存不重复保存。未来加入的新事实必须由所属领域纳入快照，不能因屏幕上没有显示而漏存。

兼容方向见[当前版本与历史退役](../compatibility.md)：只维护一套当前运行模型/写档格式，历史输入仅在明确范围内转换后进入当前模型。本节记录代码实际存在的入口，不为多代迁移或旧生成器提供永久保留承诺。

[WorldSessionSnapshot](../../../scripts/runtime/world_session_snapshot.gd)在共同时刻捕获联合快照，独立候选先恢复各域，再核跨域来源/成本/位置/占用；成功后才替换活世界与呈现引用。[SessionSaveSchema](../../../scripts/persistence/session_save_schema.gd)校验根版本并明确拒绝旧环境档，[SnapshotValues](../../../scripts/persistence/snapshot_values.gd)处理JSON值，[SimSaveStore](../../../scripts/persistence/save_store.gd)负责文件备份/原子替换。

当前代码写根53、区域44和含来源定义的内容包2；旧根不伪造Q到场响应的迁移。具体边界见[兼容性](../compatibility.md)与[环境合同](../world-environment-contract.md)。历史没有的知识、交易、物件和经历不能由新开局补造；当前墙门/人物位置不能证明过去的见证。同毫秒次序只能用已有序号/半开区间证明，不声称完整历史重演。围合、占地索引、缓存和纹理可重建，不作为另一份存档真值。

## 保存操作与成熟能力

用户接受“暂停→保存→继续”。正式操作可先停止接受新的模拟时间，结清当前已接受步，再同步捕获/写档，结束后恢复原暂停状态；不要求实现无停顿后台快照，也不必等人物完成整段旅行。目前`save_game()`是同步调用，检查共同时间/领域事务已完成后才捕获，繁忙则返回`ERR_BUSY`；**尚未自动实现上述暂停与恢复编排**。失败保留主档/备份，不把空快照当成功。

底层已用Godot自带`FileAccess + JSON`，临时文件验证、保留上一份备份后替换主档。文件层只处理编码/读写，领域定义自己的状态，独立候选通过后才替换活世界。JSON便于当前调试；若实际大档测量证明瓶颈，优先评估内置`store_var/get_var`与压缩，而不是自创序列化器。更换编码不会自动减少领域数据或恢复校验成本，本包不为此重写格式。

2026-11-07有界调研（静态资料，不是插件安装或性能验收）：

- [Godot官方Saving games](https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html)与[FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html)：项目确定需保存的数据，再用内置JSON或二进制序列化写入；这已是当前采用路线。
- [ResourceSaver](https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html)提供Resource文本/二进制保存，适用于Resource数据组织；不自动识别未加载远区、领域唯一所有者和进行中过程。不为换工具把现有纯数据强制改成Resource树。
- [Save Made Easy 1.3](https://godotengine.org/asset-library/asset/2056)（MIT，库条目标注Godot4.1）：便捷嵌套键值/Resource转换，底层仍是FileAccess/JSON。[所读源码](https://github.com/AdamKormos/SaveMadeEasy/blob/0cd7aae70fda98487f0eef8370e23c63217f141f/addons/save_system/save_system.gd)直接写目标文件，没有提供当前项目所需的完整世界候选恢复合同。
- [SaveSystem 1.0.1](https://godotengine.org/asset-library/asset/4832)（MIT，标注Godot4.5+）：轻量键值及Variant文本读写。[所读源码](https://github.com/TommyKooij/SaveSystem/blob/47178f120d8d35f7f0430b52dc94f27b52c96352/addons/SaveSystem/save_system.gd)不能替代项目状态装配；采用前仍需目标引擎兼容验证。

本次决定保留内置能力上的薄文件层，不安装这两个插件、不扩多代迁移或历史重放。必要验收是当前世界保存、完整退出、重启恢复以及关键进行中过程接续；新领域接入时补其缺失状态，不围绕单件样品无限扩展。
