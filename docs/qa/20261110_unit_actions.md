# 完整单位行动与交互验收

状态：2026-11-10，`codex/unit-actions-integration`在验。以环境最终`337ea13e6bfb89321d2fda9eef26f5612dc65cd9`为起点，当前根56/区域47/内容包3/环境5。最终受检SHA和主审在收口时补齐；本页不把定向结果当完整回归。

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

待记录：最新定向、最终布局、主审、最终生产/测试SHA与对应完整结果。main尚未合入。兼容拒绝旧档保持原文件，不承诺根55迁入；新建世界可体验当前入口。
