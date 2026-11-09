# 环境跨领域组合验收

2026-11-09，分支`codex/environment-composition`承接`388080210843e83aeae7efa130388d92b2cbc904`；本页记录本轮实现及证据，不重开旧Goal。最终提交/回归与主线状态待收尾写入HANDOFF/BASELINE。

## 交付边界

原环境域复用结算/事件、原空间与通用SL，新增派生`SimEnvironmentLayout`，不持第二份温度。木/石墙、门窗和岩地按通道透过；覆顶房间充分混合，分合/开敞承接旧实际温度。材料库存、携物和箱体暴露沿原owner；跨格通知来自原1ms运动积分。植物读取同一温度和自然/人工总光。`context_at`只组合真实条件供开发/未来堪舆方法使用，不写角色认识或生成吉凶值。

Godot继续负责场景/脚本组合、signal、资源和呈现；现有PhysicsServer2D/碰撞能力不重复实现。本包的房温/五行与业务时间属于游戏专属规则，没有新增物理引擎、autoload、事件总线或中央存读链。成熟公开参考及证据边界见[研究](../../design/research/simulation_events.md)，采用合同见[环境合同](../engineering/world-environment-contract.md)。

当前写档根55/区域46/环境5/composed_fields_v1，内容包3。旧root54室外模型按政策拒绝，历史fixture及用户档保留。恢复重建布局/来源/缓存，验证同房锚点、目标/tau/覆盖后才替换联合候选。

## 定向与反例

- doctor与import通过；早期选组发现未追踪格初始化不足，改由原环境域提供实际初值。
- `logs/environment-directed.log`：施工框架、环境组合、地形编辑3组306检查/0失败，退出0；计时报告`logs/test-timings-1794237701763195600.jsonl`。
- 新环境组保护真实材质传播、实际缓存失效、一房一温、开门tau、分隔/合房的旧值平均、损毁承接、箱内材料实际存放/暴露、跨格全段/任意分片同未来、人工照明及坏候选不改活世界。原施工组保护克隆库存提交与在途储藏/生产，地形组保护实际编辑和独立候选恢复。
- 扩域中实测的拒绝：旧fixture直接写库存没有通知；实际生产/浇水/植物产物等克隆库存提交漏通知；地图变化没有传播失效；房温平均留下JSON会舍去的二进制尾差。已沿原owner接变化通知、补可定位原批次/资源锚点，并在房间目标发布与恢复验证前统一数值表示；没有删断言或放宽候选门禁。原地形测试完整复验通过。

## 普通Main与完整停开

`tools/qa/environment_composition_probe.gd`基于原普通Main探针；独立验收，不加入每次回归。使用自己测试存档，未替换普通玩家槽。

首进程报告`logs/environment-composition-native.json`：Godot4.7.2、D3D12/Forward+、RTX5060Ti，failures=[]。真实房间读取同一温度；预算1排队保存，86帧结清已受理区间，checkpoint `d27d92faf044b3d536e9cc03bf85ce669432f24b09fac13ad608943e159f0b5b`，未来250ms `242525df6e79726d359d486d66f5e83ccaca4c5ec1125f525fb5154ec0d3e84f`。独立第二进程`--resume`退出0，日志`logs/environment-native-resume.log`确认两个hash完全相同且failures=[]。

已实际查看`logs/environment-composition-native.png`：普通HUD/旅行、日照、局部场景与原面板正常呈现。180帧/6株、60预热帧及402流式等待帧；P95 30.545ms/P99 34.217ms/max34.340ms，欠算峰值37ms，engine static约360MB。一分钟实际推进935.297ms/16让出帧。这是该机器的小样本，当前不能宣称60fps或16GB整机/RTX3060级密集世界目标通过。

## 限制与待验

射线不模拟绕角，房温充分混合/tau不严格守恒；材质/开口参数可调。来源候选和低频布局/响应刷新仍同步CPU，单次回调不能被宿主预算抢占；通用嵌套、独特器物入箱、人物体质/鸟兽本体源、空气质量和完整风水玩法未实现。人工光仍有明确有界查询上限。

最终完整回归、原生Sol/custom静态审查、最终SHA与push证据待本包收尾；不得把本页阶段选组当作完整通过。
