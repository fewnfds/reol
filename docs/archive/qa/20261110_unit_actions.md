# 完整单位行动与交互验收

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

状态：2026-11-10，按用户授权整合main，最终生产/测试`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`。以环境最终`337ea13e6bfb89321d2fda9eef26f5612dc65cd9`为起点，主体`68fff8b35e90617f4e95b416cdacf73834e6bf5e`，当前根56/区域47/内容包3/环境5。对应CI42750266714已核completed/success；定向与合并状态本身不作为完整通过依据。

## 范围与真实修复

- `SimGridNavigation`复用Godot AStar2D及原净空；原身体位置、原route及领域成本不迁入新状态库。受阻在共同时间边界重评，保持ID/预约；固定证据行旅和规定步法仍按原遇阻中断。
- 原services持数量搬运jobs与跨账本回执，原库存持数量/预约/保管，建筑仍持容量和操作位；原codec登记scope，无中央SL重写。普通“搬运”页提交同一入口，NPC可复用。
- 工作、交互和有限交锋共享原身体/控制/时间，`SimActionContract`提供投影/终态，原`interrupt_occupation`集中中断；不新增第二套任务或物理引擎。
- 环境旧CI42659346260确为失败。首错仅两个phase initial在完整检查点漂移，非机器慢；最小原生复现显示`JSON.parse_string(JSON.stringify(..., full_precision=true))`仍可移动这些double的末位。恢复使用模型已有1e-9锚点精度，连续三次停开反例及原`test_world_persistence`通过；未放宽比较。

## 定向证据

Godot 4.7.2 stable标准版，doctor/import已核。日志均在本机`logs/`，不随仓库提交。

| 证据 | 结果与限制 |
|---|---|
| `unit-navigation-directed.log` | 中间版3组115检查：普通搜索、多格几何与大身体 |
| `unit-actions-core-directed.log` | 中间版5组384检查：搬运、原取放、移动、共同行动与护障走位 |
| `hauling-routing-directed.log` | 中间版2组49检查：跨账本/保管/续送/候选原子性/foreign预约，原native ID绕行与37ms切片同未来、真实敌意中断 |
| `unit-actions-domains-directed.log` | 首轮7组中休息旧“必须取消”断言失败；改验可达绕行仍持原床位，未删除断言 |
| `unit-actions-recovery-directed.log` | 7组2277检查退出0：phase/temperature锚点、普通Main存读、休息、制作、搬运/路线；后续面板/候选边界另验 |
| `unit-actions-runtime-directed.log` | 9组822检查退出0：搬运/路线、版本拒绝、共同行动、完整发布、战斗运行层/走位、原服务面板及安全保存 |
| `unit-actions-storage-directed.log` | 最新5组449检查退出0：搬运/路线、约练/交锋、建筑；容量/操作位与损毁不吞货，补箱体自遮挡反例及坏候选字段拒绝 |

## 原生Main与独立停开

`tools/qa/unit_actions_probe.gd`实例化普通Main，选择山门杂役；用普通搬运表单提交，走到原库取货，途中保存到独立QA slot，再实际交付。完整world/clock/motion的检查点及未来hash都比较，不只比较物资数。

原生进程退出后再以`--resume`启动，检查点相同，3287ms后整个世界未来hash为`3356a079ce969e8fa7f2ab903bcd99a3437a20ecbc873491af45e7e986ff3945`，同进程与独立进程一致。日志`unit-actions-native.log`、`unit-actions-resumed.log`及JSON报告保留；截图`unit-actions-hauling.png`、`unit-actions-combat.png`、`unit-actions-resumed.png`已查看。GPU实际为RTX5060Ti，不是RTX3060性能证明。

同一普通流程到场请石头真实示范一分钟，学会气弹；NPC与玩家使用相同搬运入口。取货后普通U入口表明敌意，工作取消而原公物/责任仍在；E入口发射原飞行物，退让不能私吞公物。初次选择的居民已走远，规则正确拒绝；验收改为两人沿相同工作路线，未传送身体/修改感知或战斗规则。

画面发现搬运长表单遮住顶部时间按钮，改用Godot ScrollContainer限制表单高度；最终布局复核包含面板边界与滚动后按钮截图。固定截图不代表完整手感、致死战斗、群战、负重或密集规模验收。

## 最终收口

主代理对主体只调用一次`codex -c model='"gpt-6.1-sol"' review --commit 68fff8b35e90617f4e95b416cdacf73834e6bf5e`，custom路由保留，退出0；审查只做静态分析，无第二套测试/递归审查。日志`unit-actions-native-review.log`。确认2项P1和1项P2，均先在`unit-actions-review-red.log`复现：

- 手动闪身错误结束原约练，导致起势中滑动或丢失bout；手动运动保留原约练/阶段限制，显式停止与敌意接触仍完整中断。
- 公物经箱体可变为私物；当前不伪造完整产权模型，公物只交登记公共地点或随身保管，禁止转入普通箱体，私人材料仍可存取。
- 在途候选可篡改stand远程交付；恢复绑定原端点/操作位，并在到场取放前复核接触，失败不改活世界。

修复后`unit-actions-review-green.log` **5组223检查，退出0**，覆盖三项反例及原服务/走位接缝。最终原生和独立进程日志均退出0、failures为空，整个checkpoint及3287ms未来hash保持上述值。ScrollContainer布局在1280×720保留时间与停止按钮；截图已查看。

前版生产/测试`0a0b59a15088f53f762bec13bc20b9145923402b`的[CI42674488111](https://github.com/fewnfds/reol/actions/runs/42674488111)在本轮整合点核为completed/failure：第5片感知测试仍要求绕墙者保持原y坐标，第11片休息界面漏认`sleep`阶段。两项在本机原代码复现；错误日志为`logs/unit-actions-ci-42674488111-failed.log`与`unit-actions-integration-red-timings.jsonl`。

收尾`0856effd4b2bb135c9bae8f25cccbba0e3def8e0`修复休息显示，并以相同已知线索、不同隐藏坐标的独立世界对照保护感知边界，允许合法绕障；不改寻路/感知规则或放宽数值容差。休息/原服务运行2组88检查通过，最终感知组108检查通过；计时为`unit-actions-integration-green-timings.jsonl`及`unit-actions-integration-perception-final-timings.jsonl`，不是全套覆盖。

本收尾包一次Sol/custom原生静态审查，宿主不能启动命令后接续同一会话`01a1c385-40f3-74f1-bac7-bb3cd069795e`，提供准确Git差异/源码完成分析，退出0、无可操作发现；`unit-actions-integration-review-resumed.log`保留证据。收尾代码的[CI42750266714](https://github.com/fewnfds/reol/actions/runs/42750266714)在本次试玩修复提交点精确核为completed/success；完整CI通过，不轮询。

本轮按用户授权将通用SL、事件/植物、环境组合和行动历史一起快进整合main；试玩修复与诊断后续另分支，不混入此集成包。旧档原文件保留，不承诺根55迁入；新建世界可体验当前入口。
