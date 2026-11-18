# Reol

GDScript / Godot 4.7的纯二维斜俯视修仙模拟世界。当前正常开局为青禾宗四院100人：玩家控制一人，其余99人按各自认识、需要、目的与职责自主生活。

双击根目录唯一的[启动.cmd](启动.cmd)，选 **2** 运行最新源码宗门，选 **3** 运行宗门独立成品；选1保留源码战斗练习，选5保留旧P5战斗包。独立成品位于`build/windows/sect-foundation/`，exe与pck须放在一起。源码修改后重启生效；导出包是生成时快照。[运行与导出](docs/engineering/tooling/usage.md)。

宗门的井、田、粮仓、灶台和餐箱使用真实物资。居民会耕作、照料、采收、加工、取食和休养，也会求学、授业、练习与办理已接受的事项。设施、人物起点和任职由Godot原生Resource装配，共用原World与行动框架。战斗P4机制及P5决策仍保留；阶段完成证据与限制见[主计划](docs/plans/foundation-priorities.md)和[构建验证](docs/status/baseline.md)。

初次试玩：

- 金圈是你，WASD移动；默认日常，左键选人或设施、右键交互；Tab切换战斗。
- 点击左下角“职责”管理有权部门：安排人员/工作组、下生产目标并绑定工作台、设置仓储和供料。普通成员只看本人工作，自定义头衔不自动授权。
- 点同门后打开“人物”，可看外显状态、当前活动、同组织公开职责和住所。私人背包、内心目标与精确修持数值属于本人；离场人物显示已经取得的旧线索。
- 到餐箱进食、回自己的床休养；找“传功弟子”请教，再到灵植旁练习。玩家与NPC使用相同投入与接近规则。
- 采集材料后放蓝图，点“协作”选择同门，主角会当面请求。NPC可以拒绝；接受后还需实际办理，人物“约定”页可发起当面核对。
- F5保存，关闭重开后F9接续。当前源码使用`sect-quicksave-v33.reol`；宗门包格式见构建验证，位于`%APPDATA%/Godot/app_userdata/reol/`；旧P5包的format14文件另存。

按主题查[记忆地图](docs/README.md)；未完任务见[HANDOFF](docs/status/handoff.md)，agent入口为[AGENTS](AGENTS.md)。

- [可玩能力、键位和明确未迁回的玩法](docs/status/features.md)
- [实际性能与构建](docs/status/baseline.md)
- [运行和导出命令](docs/engineering/tooling/usage.md)
- [当前运行架构](docs/engineering/architecture.md)与[唯一主计划](docs/plans/foundation-priorities.md)
- [产品愿景](design/vision.md)、[已定规则](design/rules/README.md)、[文档职责](docs/DOCUMENTATION.md)

构建产物不入库。新检出安装Godot 4.7.2和Python后可直接运行源码入口；独立包按[导出命令](docs/engineering/tooling/usage.md)生成。退役实现与旧报告由[Git历史](docs/archive/README.md)追溯。代码许可证尚未选定，第三方来源见[NOTICES](THIRD_PARTY_NOTICES.md)。
