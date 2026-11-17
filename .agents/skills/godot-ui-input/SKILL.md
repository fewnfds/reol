---
name: godot-ui-input
description: 设计、修改或review Reol的HUD、窗口、背包、焦点、按键绑定与世界输入交接时使用；不负责模拟行动规则。
---

# 界面与输入边界

本地合并重写原game-ui-ux、godot-ui-control、input-systems；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。沿`presentation/ui/hud.gd`、`interaction.gd`、`input_bindings.gd`及原面板扩展，按钮与热键调用同一命令入口。

## 输入与对象

- 区分边沿命令和持续意图，按键重复不能重复消费一次动作。动作定义、显示键名和本机绑定使用同一来源；物理键与逻辑字符的选择须与当前控制方式一致，不在提示里写死键名。
- 普通世界点击接GUI未处理事件；Control处理控件输入。`_input`早于GUI，不能先攻击再让按钮消费。`MOUSE_FILTER_PASS`向祖先传递，不表示穿透到兄弟；装饰节点是否IGNORE按实际层级检查。
- GUI消费事件**不会清除**`Input.is_action_pressed`的全局按住状态。模态、文字输入、改键捕获、失焦、暂停、战斗/日常切换沿原直接控制代次边界清持续输入与未启动缓冲；不能仅靠抬键事件，也不能开关窗口取消已经提交的动作。
- 焦点按当前输入方式明确分配：点过按钮后，`ui_accept`/方向键是否还会误触或截走世界控制；需要键盘导航的菜单保可达焦点，不一律设FOCUS_NONE。文本框与改键捕获之间独占输入，按需释放文本焦点并先消费捕获事件，Esc分层退出；关闭模态后恢复仍有效的原焦点。
- 选中身份、当前操作人、目标与角色参数必须明确；受理、等待、拒绝和实际完成分别显示。普通面板走`subject_view.gd`的可知白名单，不用诊断全视图给NPC泄露隐藏状态，也不开窗即更新个人认识。

## 布局与更新

- Container负责其子项布局，anchors/offsets用于相应自由布局；用minimum size、size flags和Theme处理长文本/缩放，不一概禁用必要的局部像素布局。不要同时动画和Container写同一个布局属性。
- Theme/StyleBox也是共享Resource，局部样式用适当override或有意隔离的副本，不能改一个面板就意外改变全部使用者。
- HUD缩放、Viewport、世界相机是不同坐标系，点击/拖拽经与绘制相反的变换；改变UI比例不改变世界身体坐标。当前缩放只在HUD父Control，别另加Window缩放造成二次缩放。
- 变化通知或Frame版本驱动相关控件更新；连续进度可按显示时钟插值。复用正在交互的格子，不每次刷新销毁焦点/鼠标目标，也不每NPC创建一套后台控件。
- 给不可执行操作可理解的对象和原因；进度反映实际活动，不伪造前进。状态不能仅靠颜色区分。当前支持的窗口/输入方式先做到可读可操作，手柄/手机不是本技能自动追加的产品范围。

输入/布局变化用真实窗口核一个正常与一个边界场景：长中文和缩放/窄窗口、点击UI不触发世界、按住时开关模态/失焦、关闭后焦点返回。只运行headless看不到输入消费与最终渲染；不必每次全排列所有设备。

官方依据：[输入传播](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)、[Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)、[多分辨率](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html)。
