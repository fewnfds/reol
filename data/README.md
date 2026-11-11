# 内容数据与开局

这里保存内容输入，不保存活世界。当前数据是旧Demo的可用素材和回归输入，可以在重构时按新装配接口迁移；文件名、混合schema或历史版本不构成必须维持的架构。

## 当前目录与使用边界

| 目录 | 当前数量 | 作用 |
|---|---|---|
| definitions/ | 43份JSON | 共享定义及规则参数：身体/原物、空间设施、自然/环境、行动、社会/认识和修行方法 |
| scenarios/ | 13份JSON | 新局、地图/地理、双聚落、植物/器物/生命等初始装配 |
| compatibility/ | 1份JSON | `content_db_v42.json`是旧内容基线，只供明确的兼容/拒绝验证；不是普通新局输入或可玩旧模型 |

本次静态核对57份JSON均可解析且均有代码或测试文件名引用；引用存在不等于全部进入普通Main。真实装配由[ReolContentDB](../scripts/data/content_db.gd)、[ReolWorldAssemblyInputs](../scripts/data/world_assembly_inputs.gd)及对应runtime决定。现行内容包版本见[BASELINE](../docs/status/baseline.md)，不按单个JSON的`version`推断整个包版本。

## 内容分工

- 世界/环境：`natural_environment`、`climate`、`weather`、`environment_sources`；`local_heat`保留当前设备参数语义，不能把路径名当成第二环境状态。
- 身体/器物：`pawns`、`origins`、`ranks`、`body_forms`、`artifacts`、`clothing`、`soul_vessels`。
- 建筑/生活设施：`construction`、`workplaces`、`resting`、`personal_production`，按真实设施/材料与原库存组合。
- 植物/生命：`plants`、`land_resources`、`avian_life`、`large_bodies`，对象只参与实际能力。
- 行动/健康：`local_actions`、`conflicts`、`sparring`、`health`，定义不持有在途动作或伤势。
- 认识/事务/方法：交互、服务、工作、库存信息、能力、修行和来源照护等文件，由对应领域装配，不统一塞进人物模板。

以上为阅读分组，唯一机器清单仍是实际加载器；不另建手工内容注册表。开局位置/数量与可复用规则应分离；当前`village.json`仍混有两类输入，这是旧装配事实，迁入新结构时允许重拆。

## 写入与迁移约束

1. 定义、开局与实例分开。运行中的位置、数量、伤势、钱货、知识、过程和随机状态不回写模板。
2. 会话使用完整一致的规则/生成描述；读档不从当前磁盘模板补造缺失历史或再次发行开局物资。
3. 开发期只支持[当前存档格式](../docs/engineering/compatibility.md)，不维护历史fixture或迁移链。
4. JSON语法、字段值域、定义引用和跨域合法性分别验证。静态盘点不替代游戏装配与行为测试。
5. 日志、性能结果、缓存、用户存档和生成截图放各自输出位置，不混入内容输入；数据保存见[存读管线](../docs/engineering/architecture/04-persistence.md)。
