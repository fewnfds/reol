---
name: godot-resources
description: 设计或review Reol的Resource结构、编译目录、复制隔离与加载时使用；单份已有定义调参或改字不触发，运行存档另用save-systems。
---

# 作者数据与实例隔离

本地重写原godot-resources；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。作者入口是`scripts/sim/definitions/`和`data/definitions/`，运行目录还经过`kernel/action_defs.gd`、`items.gd`等对应桥接；定位本次库的`values()`、`errors()`、冻结与内容签名，沿原目录扩展。

- Resource是可共享的作者定义；冷却、血量、计时、在途载荷等实例状态仍归原owner。不得通过修改加载的`.tres`给某个单位升级，或在UI中修改所有使用者共享的材质/Theme。
- 校验不只看Inspector范围：检查空引用、唯一ID、交叉引用、有限数值、数组边界和可执行组合。作者数据与编译结果的字段/签名同步，失败候选不发布；现有定义编译为规范只读值，不需为每个单位深拷贝整个目录。
- 明确哪层需要独立：Array/Dictionary的`duplicate(true)`仍共享其中的Resource。Resource的`duplicate(true)`会递归容器，但不会无条件复制所有外部Resource；需要复制全部子资源时核`duplicate_deep()`模式及代价。`resource_local_to_scene`主要在场景实例化时生效，不是运行中随手开关就能隔离已有对象。
- `duplicate`受自定义必填`_init`参数和属性usage标志影响。若本次依赖隔离，用两个实例实际修改最内层字段，证明该独立的独立、该共享的仍共享；不能仅断言顶层引用不同。
- `ResourceLoader`缓存使同路径加载可能返回同一对象。后台加载也不允许同时改共享Resource或活SceneTree；未完成先不调用阻塞取得结果，采用时核会话。资源文件改变、内存对象改变与保存落盘是三件事。
- `.tres`/`.tscn`引用保持真实路径大小写与UID，新增UID由Godot生成；运行数据写`user://`，不要向导出包内`res://`写进度。Resource加载会构造脚本对象，不用它反序列化不可信存档。

只调单份已有定义数值/文案不必新建数据驱动框架或做双实例隔离反例。新增结构的验证应真正通过现有库编译并执行一例，兼顾错误输入拒绝；改变共享/复制边界时用上述双实例反例。

官方依据：[Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html)、[Dictionary复制](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)、[资源与线程](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)。
