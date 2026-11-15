# 当前短检查

`python tools/godot.py test`运行kernel_smoke.gd及其feature/sight/equipment短反例；覆盖存读、中断、导航、资源守恒和相关领域交接；512人串/并行配置至少推进1世界秒，并在两者均完成真实交付后结束该段，不固定重复6秒压力。验证强度查[开发循环](../docs/engineering/workflow/testing.md)。旧全玩法测试和CI已退役。

`tool_smoke.py`在修改Python运行或性能工具时使用，核对进程退出/超时、历史复用、单倍率次数上限及不可比条件，不启动游戏。性能用真实release短窗口，不用smoke通过数量代表容量。

`ui_smoke.gd`按需单独运行，约数秒核对实际GUI输入、共享格子数量取放、图标换装/卸下、人物与背包并排和缩放、工具取消/旋转、交互上下文和小地图只移动镜头、迷雾详情、人物事件与百分比缩放确认，不加入kernel默认套件。图形运行将本机截图写入忽略的`logs/ui-smoke/`，缩放探针不写用户偏好；不冒充全玩法人工游玩。

`equipment_smoke.gd`由kernel短检查调用，覆盖满包换装/卸下原子性、真实伤害/护甲/移速、发射后换装、品质转移、派生缓存恢复、非法槽位拒绝和身体槽位重用；原磁盘续接反例同时核对穿戴。功能性能对照独立使用[capacity入口](../docs/engineering/tooling/usage.md#功能性能对照)，不加入默认测试。

`experience_smoke.gd`按需单独运行，针对普通/压力场源分离、冷热耐受/小数余量、危险中禁止恢复、战斗不吃耐受、死亡顺序、有界个人日志与存读做短反例，不扩大kernel默认套件。

`act_smoke.gd`按需单独运行，核对已退休RTS指令拒绝、三连/锁向/短缓冲、动作承诺、步长与慢域节奏、闪步/CD、弓持续发射/松手、扇射保护、墙体积/移动折线扫掠、在飞弹跨射手死亡、生活中断释放预约、候选恢复及非法状态拒绝。`act_ui_smoke.gd`在真实图形窗口核对WASD/鼠标攻击/武器技/真装备/闪步、F交互、旧按钮移除、失焦/背包/暂停清输入及音频播放器触发；截图在`logs/act-ui/`。它们不证明正式动画、音效混音或人工试玩已收敛。

`response_smoke.gd`按需单独运行，核对Runner诊断信封的时间先后、回执绑定/只消费一次与原请求不被修改，不加入默认kernel套件。真实窗口的合成移动响应测量见[响应链实验](../docs/engineering/tooling/usage.md#响应链实验)；短检查不证明操作手感或显示器延迟。

`control_smoke.gd`覆盖P1键鼠配置的上下文冲突/安全交换/保存重载/损坏回退，旧输入代次失效、玩家与NPC缓冲的恢复边界，以及直角墙、单格门和高速身体扫掠。`control_ui_smoke.gd`在真实图形进程通过实际GUI输入改键、确认交换、Shift反复捕获、失焦清捕获、鼠标侧键触发世界动作、重启保留/恢复默认、缩放/小窗口布局、自由镜头瞄准和锁向分离；偏好使用独立测试文件并清理，截图在`logs/control-ui/`。两者按需单独运行，不扩大默认kernel套件；Windows原生Alt-Tab实查与本机走查证据见BASELINE。

`melee_smoke.gd`验证P2三连/终结收招、分类型短缓冲和失效、闪步90ms边界、箭穿避伤者/掠过身份存读、单刀无假确认、稳固/原收招保留/单次失衡、控制预算与残余击退不劫持新闪步。`melee_ui_smoke.gd`在真实图形窗口用鼠标/键盘完成轻敌三连、重敌稳固→闪步→收招重斩，检查图形会话保存/恢复不重复伤害或刷新CD、三种练习切换/死亡重开、反馈偏好/200%UI、镜头不扰瞄准及多目标音效合并/预留通道；截图在`logs/melee-ui/`。两者按需运行，不扩大默认kernel套件，不代替人类手感与主观混音判断。

`abilities_smoke.gd`验证P3递归只读定义、独立资源变体/非法时序、规则签名拒载、多人CD与激活隔离、散射/追踪与失视退化、减速/DoT和预警/区域/飞剑中途恢复；覆盖来源死亡、目标移除、到期半开区间、到期前续期当拍跳伤、飞剑损毁不吞后到弹、接回不抹早到攻击、墙阻/重合回收和非法弹状态拒绝。约数秒，按需运行，不加入默认kernel套件。

`abilities_ui_smoke.gd`继承图形输入辅助，通过原生下拉框和真实鼠标/键盘选择八套范例并施放左右键；检查状态/弹体发布、落雷预警和飞剑返航中的实际文件保存/恢复。截图在`logs/abilities-ui/`；独立测试档和偏好结束后清理。`combat_authoring_editor.tscn`在一次性Godot编辑器中加`-- --combat-authoring-check`运行，验证真实Inspector插件、范围/阶段布局与合法/非法资源提示，截图`logs/combat-authoring-editor.png`并自动退出；未带该参数时不会自动执行。具体命令见[usage](../docs/engineering/tooling/usage.md#开发期直接试玩)。

`action_foundation_smoke.gd`核对公共门禁、陈旧run通知、正常收招后的续段、一次终止、坏载荷/幽灵预约拒载；`action_domains_smoke.gd`核对工作/伤害先后、新生短到期、手工/ACT照料消费/恢复。`action_domains_ui_smoke.gd`以原生配置选择和真实右键验证选定植物的ACT交付；截图仍归`logs/abilities-ui/`。按需运行，不扩大默认kernel套件。

P4新增检查按改动选用，不加入默认kernel长矩阵：

| 检查 | 必要反例 |
|---|---|
| `action_resources_smoke.gd` | 资源别名/多成本原子性、修饰重建、盾/格挡/真实吸血、同刻姿态和半开到期 |
| `action_reactions_smoke.gd` | 命中/定时分裂残段、兄弟共享预算、死亡传播、跨施法满层、两目标标记脚本与在途恢复、完整动作FIFO/不污染缓冲、零方向接触派生、坏lineage拒载 |
| `action_spatial_smoke.gd` | 召唤独立感知/人口需求隔离、图腾光环/可破坏受体、瞬移无隐藏避伤、双器物回收不修复；精确到期/主人死亡/单槽损坏/地图边缘与身体页扩容；受控随从周期、定义持有规则恢复、移除身体清未启动请求 |
| `action_combinations_smoke.gd` | 血刃获怒→耗怒→守势/回元、远程四槽；弹/传播/双盾/狼/图腾/双剑共存恢复后结果一致；合法取消后不继承旧惩戒窗口 |
| `action_combinations_ui_smoke.gd` | 真实键鼠左右键/E/C、原生配置切换、多槽HUD、两条组合及机制显示、四种实际文件存读、旧选中对象不可见仍可出招 |

P4 GUI截图归`logs/abilities-ui/p4-*`，独立测试档/偏好自动清理。`combat_authoring_editor.tscn`另覆盖共同Status/Reaction/Loadout Resource校验、缺失template和嵌套/跨类型引用提示，不只验证Ability预览；定义规则还验证坏Loadout短路与原生DoT周期一致性。通过这些检查不等于正式手感、长局或密弹容量验收。
