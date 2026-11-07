# 对象与空间查询接口

本页描述当前对象描述、历史快照与实时空间合同。验证范围见[首包QA](../qa/20261105_world_object_contract.md)及[共同空间阶段QA](../qa/20261107_world_space_actions.md)。不把读取能力当作创造、移动或行动权限。

## 入口与归属

[RegionalSimulation](../../scripts/sim/regional_simulation.gd) 提供 `describe_object(reference)`、`object_capability(reference, capability)`、`capture_object_space(references, budget)`；由 [SimWorldObjectQuery](../../scripts/sim/world_object_query.gd) 适配原领域。没有新增 Singleton、对象状态库、位置所有者、时钟或存档格式。

| reference | 实际原所有者与含义 |
|---|---|
| `{kind: actor/avian/artifact/large_body, id}` | 复用 `SimEntityQuery`；身体、鸟、器物、大兽各归原域，裸 ID 可同名 |
| `{kind: stock, domain: village/avian, region, container, item}` | 原容器的类型数量条目；不存在和已有零数量可区分，没有独立实物 ID |
| `{kind: resource, region, id}` | 原 `SimLandResources` 的有限来源记录；位置沿 source→place，货量来自原库存，不能据此宣称独立植物已实现 |
| 原 `construction`/`workplace` 引用 | 复用 `SimStructureQuery`；墙或屋顶组件的多个格引用同一记录，蓝图保持未建状态 |

结果包含独立复制的引用、分类、属性、能力声明以及空间投影；不返回原 Dictionary 的可写别名。数量查询只读原数量，不扫描预约/保管求可支配数量；操作的合法性仍由原库存规则判断。能力声明来自原形态/器物定义，新增同能力内容不按其名称增加分支；不同协议的新机制仍需要领域实现。

## 时间、能力和空间语义

- `state_owner`、`location_owner`及其各自时刻保留真实归属；`record_region` 是保存关联，不能当作人物所在空间区。
- `world_time_ms` 为已提交共同时间，`target_time_ms` 可有积压；`stale` 和 `world_has_backlog` 分别表示来源滞后与共同目标未完成。查询不同步远区，不预测未来。
- 能力使用命名空间：body_form、artifact_definition、inventory_entry、resource_record、structure_geometry。已声明、该空间可识别但未声明、该协议不支持的能力三者分开；已声明不代表当前能执行。
- `spatial.cells` 是格投影，不是连续碰撞、多格扫掠或寻路授权。ground/air/roof/container/planned 分层，body/placed/contained/resource/blueprint 表示关系；携带物和数量条目不会因跟随容器锚点而成为地面堆或障碍。
- 目前身体几何沿原奇数矩形合同，资源沿现有 512 地图边界；不声称任意形态、全家具或完整植物已经支持。

## 显式空间快照

[SimObjectSpatialSnapshot](../../scripts/sim/object_spatial_snapshot.gd) 仅捕获调用者提供的引用集合。世界入口一次最多 4096 引用、65536 格，拒绝来源滞后/时间欠算和重复引用；完整成功后才返回封存实例。跨域的单次描述仍沿原协议与校验，不是硬实时 deadline 保证。

快照按 16×16 桶保存精确格链接，格/对象/链使用 packed 数组；同一非矩形组件不会填满其包围盒，多格命中只返回一次引用。查询分别计访问桶、候选格和结果解码的工作，默认 4096 单位；用尽返回 `budget_exhausted`、`complete=false`，不发布部分集合。静态快照没有 tick、后台扫描或场景 `Node`。

底层独立索引最多 262144 个引用、1048576 个格链接，单引用最多 4096 格，坐标范围 0–8191；这是数据结构上限，不是普通世界容量或支持地图大小。单对象查询返回的格数依原已验证领域规则，不能借快照上限推导原 owner 支持任意尺寸。

结果恒声明 `scope=captured_references`、`live=false` 和捕获时刻。同毫秒也可能发生变更。调用者在原状态变更/加载后必须丢弃并重新捕获，不把历史缓存用于新的写入授权。

## 实时局部空间

`RegionalSimulation.query_space(area: Rect2i, kinds=[], layer="", budget=4096)`由[SimWorldSpace](../../scripts/sim/world_space.gd)组合原索引。支持当前512²地图内最多4096格的矩形，工作预算1–65536；成功才返回去重、稳定排序的完整`references`，声明`scope=world_space`、`live=true`、`geometry=cell_projection`、`visibility=authority_only`。非法范围/层、未支持类型、预算耗尽、来源滞后和共同时间待算均明确失败且不发布部分集合；查询不同步或推进世界。

| 接入范围 | 原来源与语义 |
|---|---|
| `actor`、`avian`、`large_body` | 原身体位置与形态占地；人类/行旅/各原域路线和手动运动跨格通知，雀升降层也更新。死亡不抹去仍留在原地的身体 |
| `artifact`、`stock` | 地面实物和数量堆直接查`SimGroundPlacements`；`site:`原物使用可重建格链接。本人/场所容器内物不冒充地面物；普通观察仍保留原容器候选接口 |
| `construction`、`workplace` | 原项目索引与固定组件的准确格集合；纸面为`planned`，已建为`ground`或`roof`，空洞不填满；撤图、建拆和门变化更新 |

实时层为`ground/air/roof/planned`；不枚举资源记录为植物，不枚举包含物、衣物或全部未来领域。净空、扫掠、接触和路径仍读原`SimMotionClearance`/`SimConflictSpace`等规则，格投影本身不授予可达或可操作结论。

首次查询把`prepare()`重建计入预算，也可显式`world.space.prepare(budget)`。重建只遍历现有身体、有限固定组件及原旧物候选，受管地面物沿原索引；稳定查询逐个计费访问局部格、候选和实际几何，预算用尽立即退出，不预先复制密集格的全部候选；不每次扫描全体物品/身体。预算是结构性工作量合同，单次原描述不是硬实时deadline；支持密度按实际证据声明。

`world.space.changed(change)`提供冻结的原引用、旧/新格、原因、共同时刻和服务修订。已准备的身体投影随原位置writer更新；该更新只解析原几何，不把区域推进中领先世界的来源时刻当作全量索引失效。雀/大兽一次结算的全部变化保持批次标记，回调中的查询返回`pending_projection`直到整批链接更新。生命周期在原物/库存/环境事务提交后通知，结构在原索引提交后通知；尚未准备或恢复失效时用`projection_invalidated/restored`表示整份派生链接需重建。消费者先失效缓存，再按需要重新查询；边界内其他来源尚未同步时允许明确拒绝，不能把拒绝当作空地。

`revision`只描述该服务的格投影变化；同格内连续移动继续读原位置，不增加修订。`world_id/space_id`仅区分本进程原世界和服务，不是存档身份。完整候选失败保留旧服务，成功后创建新服务；普通`load_game`也退役旧世界的服务。旧handle返回`world_replaced`，消费者重新从当前`world_sim.space`取得；派生链接/通知不写档、不重放。

## 信息与持久化边界

以上属于开发者/权威侧接口，不直接接玩家 UI。玩家观察必须沿实际感知和知识过滤。快照不序列化、不给世界新增存档字段；保存恢复后按原 owner 重新捕获，不把派生缓存当第二份实物。
