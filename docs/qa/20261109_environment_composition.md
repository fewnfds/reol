# 环境跨领域组合验收

2026-11-09至11-10，分支`codex/environment-composition`承接`388080210843e83aeae7efa130388d92b2cbc904`；主体`2ec88b7efec3724b065224443fbbbaa820d8f0c6`，最终生产/测试`89f47163d30e172d0b858fdf8167b84ae8c208bd`，之后仅Markdown。分支推送，未合main；准确HEAD完整CI仍待核。本页记录本轮实现及证据，不重开旧Goal。

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

修复后首进程报告`logs/environment-composition-native.json`：Godot4.7.2、D3D12/Forward+、RTX5060Ti，failures=[]，退出0且无脚本错误。真实房间读取同一温度；预算1排队保存，86帧结清已受理区间，checkpoint `33bb1edd5318fe348716ef6894fd4ba6136e314058fdd514bf9ee4e11908525a`，未来250ms `ad6548fb11aadc6d8034e9ec3f048a0ae1fe060f27ec2cdbb9216b0b13aea2cd`。独立第二进程`--resume`退出0，日志`logs/environment-native-final.log`/`logs/environment-native-final-resume.log`确认两个hash完全相同且failures=[]。主体旧报告保留为`logs/environment-composition-native-2ec88b7.json`，不与最终版本混用。

已实际查看修复后的`logs/environment-composition-native.png`：普通HUD/旅行、日照、局部场景与原面板正常呈现。180帧/6株、60预热帧及402流式等待帧；P95 16.753ms/P99 33.585ms/max33.976ms，欠算峰值50ms，engine static约360MB。一分钟实际推进934.180ms/16让出帧。不能用这次对主体30.545ms的单次P95差异推导整体优化倍数；这是该机器的小样本，尚非稳定60fps或16GB整机/RTX3060级密集世界目标验收。

## 审查与完整回归诊断

主体完整`python tools/godot.py check --test-timeout 3600`已结束：导入0、测试124，162组完成后累计超时，最后开始`test_player_avatar`；日志`logs/environment-full-check.log`。其中有旧地形fixture漏通知、纯五行源导致远区温度同步、移动分片未来不一致及已退役的室外无隔热断言，不能算完整通过，也不加长超时。

一次`codex -c model='"gpt-6.1-sol"' review --commit 2ec88b7efec3724b065224443fbbbaa820d8f0c6`沿custom路由完成，只读静态，退出0；日志`logs/environment-code-review.log`。两项P2：自动格路携物缺实际跨格时刻、公开空间metadata复制完整房间成员。修复沿原`SimRouteTravel`/身体signal及`SimEnclosedSpace`，不另建运动或房间系统；增加八向/非格心的首个跨格毫秒检查、自动携物分片反例和公开固定大小metadata断言。原全量中的`test_intrinsic_light`已提供修复前的五行未来差异反例。

首轮修复定向`logs/environment-fixes-directed.log`的温度、环境组合、随身光和建筑组通过，但artifact drawing夹具调用的typed Array错误使包装器退出1；已修正，不能把那轮称作成功。静态profiling选组`logs/environment-profile.log`的环境组合125/运动68检查通过，无脚本错误；这只证明两组，不能用15秒对40秒的单次波动归因缓存收益。地形阻隔/单受体透过率缓存的收益仍需同负载测量。

`logs/environment-final-directed.log`：12组中11组2452检查通过，world space两项失败。原因是其低层fixture手动推进身体/世界时钟，却未结原环境区间，导致之后真实推进被拒绝；补齐该fixture并断言每次推进结果。`logs/environment-space-fix.log`重跑该组94检查通过，退出0；其余生产/测试保持上述11组版本，合计当前定向12组2546检查。没有用选组覆盖冒充完整注册表。

一次性同负载几何基准`logs/environment-geometry-bench.log`：16源、1024受体、4次移动，两种缓存结果SHA均为`ec6ef661f7fdd742aee7b890e6081c06802f74112e45a72dadfa9aa174158ad1`，地形查询2936→152次，墙钟161.164→151.171ms。参考路径使用主体的单pair复用与逐射线原地图查询；新路径使用当前单受体及布局地形缓存。只证明这个headless小样本的局部收益，不推导整个游戏或全回归加速倍数；基准留在忽略目录，不加入永久门禁。

`logs/environment-runtime-directed.log`的建筑框架、时钟/世界提交、运动净空runtime、植物、房间休息、保存会话及世界连续性runtime共7组643检查通过，退出0。源响应、储藏位置和文件保存边界在`logs/environment-state-directed.log`的3组572检查也通过，退出0；以上当前22组共3761检查。它们补查真实接缝，不代替完整注册表。

## 限制与待验

射线不模拟绕角，房温充分混合/tau不严格守恒；材质/开口参数可调。来源候选和低频布局/响应刷新仍同步CPU，单次回调不能被宿主预算抢占；通用嵌套、独特器物入箱、人物体质/鸟兽本体源、空气质量和完整风水玩法未实现。人工光仍有明确有界查询上限。

已有主审及修复定向结束，修复后普通Main/独立停开复验通过；本包结构/链接/大小检查331文档、517脚本、0错误，差异检查通过。提交前复用13d675e/CI42596694569的终态success缓存，仅为承接证据。最终推送HEAD的12片CI尚未登记run，留待下一真实提交检查点核验，不在推送后轮询；尚无对应SHA完整通过结果，不得把阶段选组当作完整通过。
