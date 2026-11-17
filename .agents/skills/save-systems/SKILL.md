---
name: save-systems
description: 修改或review Reol的持久字段、格式签名、存读、候选恢复及磁盘写入时使用；作者Resource定义另用godot-resources。
---

# 持久化与失败恢复

本地重写原save-systems；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。先读本次相关的[兼容与恢复合同](../../../docs/engineering/compatibility.md)，沿`state.gd`、`persistence.gd`、`session_io.gd`与各owner的`STATE_FIELDS`扩展。不为清理代码修改用户存档或历史fixture。

- 存权威规范值、独立身份、必要在途进度/时间和随机state；不存活Node、Callable、线程、显示Frame或可重建索引。字段加入/移除时核写入、冷校验、恢复次序和跨owner引用，加载后不靠世界推进补正非法状态。
- 快照与I/O分开：捕获时保证必要一致性，后台只读脱离值；保存不等待未完成软规划，也不能将活容器交线程后继续改。候选输入有容量限制，禁允许对象的反序列化或ResourceLoader读取用户可替换的存档脚本。
- 先核受支持格式与内容签名，再完整验证**独立候选**，包括类型、有限数值/范围、身份单调性、引用、在途互约与资源守恒；成功由owner一次采用。失败不改变活世界/原档，不把不支持主档偷偷换成另一段历史。
- 当前格式写一套模型；只有明确支持的旧输入才迁移到当前，不让运行代码永久双读旧/新字段。不要为新需求默认承诺所有历史档兼容；开发期如何升格式以现有合同和授权为准。
- 冷I/O写临时文件、核store/flush/rename错误并保已有备份恢复策略。`flush`、关闭与rename不自动构成跨平台断电原子事务；Windows也不能假定POSIX替换语义。失败报告真实阶段，清理不能删掉唯一有效档。
- 若引入JSON，核其数字解析与大于2^53的ID/seed精度，整型转换前先确认值合法，不用强转掩盖坏档；当前二进制Variant路径不因此改为JSON。`res://`是发布资源路径，进度/本机偏好各沿原`user://`入口。
- 采用新世界时换epoch、取消旧后台提案和持续输入，清表现历史/旧选中关联；已经提交效果、奖励与历史通知不重播。失败候选的线程/资源也有关闭出口。

新增存读合同验证途中接续与坏输入拒绝，比较失败前后活状态/原字节；磁盘流程修改再测真实文件、失败路径与退出重启，使用独立临时档，不覆盖玩家当前档。普通持久数值扩展不强制每次做全平台故障矩阵。

API依据：[FileAccess](https://docs.godotengine.org/en/4.7/classes/class_fileaccess.html)、[DirAccess](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html)、[JSON](https://docs.godotengine.org/en/4.7/classes/class_json.html)。
