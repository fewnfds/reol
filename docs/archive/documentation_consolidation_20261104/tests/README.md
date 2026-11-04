# 验证入口

U1-b1见`sim/test_source_loan.gd`、`runtime/test_source_loan_migration.gd`与`runtime/test_source_loan_continuity.gd`：具名当面说明/原办理签注、原source绑定/取消/期限/最后批竞争、非全知归还声明/本人亲见/他人代还、中断复用证据、公开低层入口/提前结算的原子拒绝、真实旧v36迁空与真实v37完整未来。原物/源/身体与服务共同验收；`runtime/helpers/source_loan_replay.gd`只发普通运行命令，不能注入成功。实机引息/核验去程两档完整停开和原生画面证据见[QA](../docs/qa/20261104_source_loan.md)。

U1-a超凡冲突见`sim/test_weapon_items.gd`、`test_combat_health.gd`、`test_combat_qi_ledger.gd`、`test_conflict_schema.gd`与`test_conflicts.gd`，以及runtime的`test_weapon_items_runtime.gd`、`test_conflict_runtime.gd`、`test_conflict_mobility.gd`、`test_conflict_migration.gd`、`test_conflict_archive.gd`。覆盖真实保管/付费、非整步发射、墙柜/旁人、同刻互击、气障/挫伤/教学中断、地面/走位/闪身、跨原数据所属区、旧档不补造、独立候选原子拒绝及真实v35在途接续。正常命令重放助手为`runtime/helpers/conflict_replay.gd`，实机入口`tools/qa/conflict_restart.gd`，证据和范围见[QA](../docs/qa/20261103_transcendent_conflict.md)。

U1-b0新增`sim/test_conflict_perception.gd`与`runtime/test_conflict_perception_migration.gd`：验证遮挡/高差、隐藏移位/新起势、有限最后位置、跨场来弹与无威胁飞弹、同刻线索、任意毫秒细/稀步、存读与严格候选。真实v35前摇档只读，经普通loader迁到根36/区域32/交锋2；保存现在以前的目击保持未知，首个未来边界才生成实际线索，已付成本和原历史全部保留。带旧目击的快照不能用当前人物或门墙证明过去，也不能把读档当作新观察。范围和待验项见[有限感知规格](../docs/plans/conflict_perception.md)，本轮完整检查/实机最终结果只看BASELINE。

局地余热首包用例：`sim/test_local_heat.gd`（守恒/纯投影/来源范围/稳定段）、`sim/test_heat_topology.gd`与`sim/test_local_heat_building.gd`（真实施工）、`sim/test_artifact_warming.gd`与`sim/test_local_heat_environment.gd`（原储量/身体/采样/NPC）、`runtime/test_local_heat_migration.gd`与`runtime/test_local_heat_archive.gd`（原子候选/真实v32）。进行中真实档只读，完整停开探针见`tools/qa/local_heat_restart.gd`；本包证据与限制见[QA](../docs/qa/20261103_local_heat.md)。

`python tools/godot.py check` 依次执行结构检查、导入和 tests/run_tests.gd。

独立地图见`sim/test_world_map_data.gd`与冻结旧算法`sim/helpers/legacy_world_map_oracle.gd`：逐格比较完整地图和八向静态通行；`runtime/test_world_map_runtime.gd`用活地图拒查/动态全阻挡和实际在途路径检验候选独立、引用与原子提交。原门墙/兽身/真实历史档回归保留，定向入口`tools/qa/world_map_probe.gd`，证据见[本包QA](../docs/qa/20261103_world_map_foundation.md)。不为新地图代码重写真实fixture。

身体后果/救护见`sim/test_health.gd`、`runtime/test_health_runtime.gd`；定向`tools/qa/health_probe.gd`。原温石真实伤源、医患排他/同意/原药consume、恢复脉冲/实际休息、跨聚落、坏候选及真实v29中途完整接续均有回归；历史fixture不得生成/改写。

- sim/：纯规则、资源竞争、社会知识、远区因果、批算和快照。
- runtime/：合法地形、真实行程、节点接续、输入/存读整合。
- 根目录 test_*.py：工具链测试，`python -m unittest discover -s tests -p 'test_*.py'`。

测试反映行为和边界，不只复述实现。新组注册到 run_tests.gd，异常必须非零退出。可见行为还需实际运行、读日志、1280×720截图。生成证据放忽略的 logs/ 与 artifacts/，里程碑图放 docs/qa/。

施工规则与运行整合见`sim/test_construction.gd`、`runtime/test_construction_runtime.gd`；定向入口`tools/qa/construction_probe.gd`。真实v16施工中途档验证原木料/工时、静态地形与独立候选阻挡、全新主场景同一未来；不能把已建墙硬塞进旧世界以绕过测试。

围合/床铺见`sim/test_rooms_and_rest.gd`、`runtime/test_rooms_and_rest_runtime.gd`；定向入口`tools/qa/resting_probe.gd`。真实v17保存进行中睡眠，验证原身体持续恢复、醒后实际让位和全新主场景同一未来；围合只由真实结构重算，不造虚假房间状态。

目录移动和文档整理的检查：

```bash
python tools/check_structure.py
python -m unittest discover -s tests -p 'test_*.py'
python .agents/skills/godot-nodes-scenes/scripts/check_godot_project.py . --strict
python tools/godot.py check
```

结构检查覆盖当前入口、本地 Markdown 链接和字面量资源路径；archive/、代码示例、外部网页及动态拼接路径不在其验收范围。场景树、资源 UID 与场景引用由已有 Godot 项目检查器负责，不在新脚本中另造一套。当前工作见[路线](../docs/ROADMAP.md)与[交接](../docs/HANDOFF.md)，通过的构建证据统一更新到[BASELINE](../docs/BASELINE.md)。真实历史fixture的来源见[样本记录](fixtures/README.md)，不为新实现改写它们。

私料加工见`sim/test_personal_production.gd`、`runtime/test_personal_production_runtime.gd`：原私料/受托边界、整批投入与失败、燃料/停工续工、现场成品/取回、精力与近远粗细一致、有限干药交易和联合候选。真实v25是实际自留采集后的续做中途档，测试只读，不生成/改写真实档。

预算劳动见`sim/test_budgeted_labor.gd`、`runtime/test_budgeted_labor_runtime.gd`：无钱/权限/所知需求、真实筹款/资金守恒、原生公差/受托/停工续做、期限退钱、现任验收/换任与容量失败、无重复贡献、NPC同API、粗细近远、候选坏引用和两种进行中存读。真实session_v26及wage_claim_v26来自鼠标正常流程，测试只读；历史fixture不可生成或重写。

有限交谈见`sim/test_capability_conversation.gd`、`runtime/test_capability_conversation_runtime.gd`及`tools/qa/conversation_probe.gd`，覆盖理解/意愿/专注、本人来源/旧话/不授予技能权限、旁人不可读、跨聚落/NPC同API、坏候选和正常存读。真实conversation_v26来自鼠标问答后1001ms存档，测试只读，旧v26也不补造介绍。

自主生计见`sim/test_autonomous_livelihood.gd`、`runtime/test_autonomous_livelihood_runtime.gd`与`tools/qa/livelihood_probe.gd`：个人口粮、来源/换任/同分钟先后、需求/承诺优先、无预算/封路退避、原工资/购买、近远粗细/候选及正常全自主场景存读。真实session_v27来自玩家正常购买筹公库款后离场、NPC自行劳动，测试只读。

实物衣着用例在`sim/test_clothing.gd`与`runtime/test_clothing_runtime.gd`，定向入口`tools/qa/clothing_probe.gd`；核对原身体/时间/晴雨/精力、唯一位置/穿法、近远/存读、真实新旧档。历史fixtures不由测试生成或覆盖。

历法/室外冷热用例在`sim/test_calendar_climate.gd`、`sim/test_environment.gd`与`runtime/test_environment_runtime.gd`；定向`tools/qa/environment_probe.gd`核对整数曲线、实际穿着/湿润、未来精力、NPC加减外层、近远/预算接续、候选与旧档启用和时间上限。`tools/qa/environment_archive_probe.gd`只读真实v30，两套独立主场景完成原穿衣/采样/实际跨气候区行旅，对比实机记录的完整未来；不生成或重写fixture。
