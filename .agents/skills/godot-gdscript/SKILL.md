---
name: godot-gdscript
description: 修改或review Reol的GDScript类型边界、Node生命周期、信号连接及异步回调时使用；普通常量或数据实例不必加载。
---

# GDScript与运行对象生命周期

本地重写，承接原godot-gdscript、godot-nodes-scenes、godot-signals-groups的适用检查；上游归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。语言API按项目采用版本核对，不把教程中的Node组织套入Packed模拟。

## 类型与失败边界

- 沿现有风格为公开接口、容器元素和跨帧值明确类型；具体类型可安全推断时允许`:=`。动态Variant入口先验类型、范围与缺失字段，再转入领域逻辑；强制转换不能代替验证。
- 保持已有tab缩进与命名约定，新接口按Godot风格及本目录惯例命名；不要为统一格式重写无关文件。样例的空格/C#命名不能直接混入现有脚本，具体规则按需查官方style guide。
- 明确整数除法、时间单位和数值精度；不要在实际会执行失败副作用的表达式外套`assert`，release会移除断言。运行时的拒绝/错误必须有正常返回路径。
- `class_name`属于全项目命名空间；添加/重命名时查冲突和引用，脚本/着色器移动连同`.uid`维护。`@tool`会在编辑器执行，隔离编辑器预览与真实会话，不能编辑资源就推进世界。

## 构造、连接与释放

- `new()`或`instantiate()`不代表已进入树。`@onready`、子节点引用与树服务在对应生命周期才有效；`_ready()`通常只执行一次，移出重入不要假定会再调用。`add_child`不等于会被PackedScene保存；本次若动态组装后`pack`，核相关后代的场景`owner`，不要对所有运行时节点一律重设。
- 已知依赖的命令可直接调用；信号用于通知，不以全局总线或SceneTree group替代领域身份/查询索引。审查同步回调的重入和真实扇出；发信号不自动跨线程，模拟线程经原邮箱/Frame接主线程。
- 连接和解除使用同一个Callable；重复配置、换数据源、移出树但未释放时核生命周期。普通相同Callable的重复`connect`会报错，不是必然多执行；每次新建的lambda则可能形成不同连接。不要把C#委托规则直接套到GDScript。
- 标准方法Callable的接收对象释放通常解除其关联连接，但不能据此保证匿名lambda及其捕获的其他Node、绑定参数或池内复用对象始终有效。短寿命界面订阅外部长寿命源时优先具名方法；若用lambda，保存Callable并管理解绑/捕获有效性，不依赖匿名回调自动跟随面板退出；不要每次刷新重新连接。
- `await`之后重核对象/会话/请求代次和当前承诺。若信号可能永不发出，给这次流程取消或超时出口；不要为等待动画完成而锁住世界推进。场景切换会立即移出旧场景，新场景就绪使用真实生命周期通知。

新增/移动场景与资源时可运行[引用检查器](scripts/check_godot_project.py)：`python .agents/skills/godot-gdscript/scripts/check_godot_project.py .`。它只读文本/UID，不能证明动态加载、回调行为或运行正确；普通文档路径仍用`tools/check_structure.py`。

验证选择本次真正改变的生命周期：例如配置两次仍只响应一次、关闭界面后源继续发信号、等待期间换档/删除目标。纯类型修改不强制重跑全部游戏。

官方依据：[GDScript](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html)、[Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)、[Node](https://docs.godotengine.org/en/4.7/classes/class_node.html)。
