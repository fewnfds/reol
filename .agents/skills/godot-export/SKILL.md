---
name: godot-export
description: 修改或review Reol的Windows导出预设、资源过滤、启动入口或交付独立游戏包时使用；普通源码修改不强制重新导出。
---

# 独立包与资源完整性

本地重写原godot-export；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。沿[现有命令](../../../docs/engineering/tooling/usage.md)与`tools/godot.py`导出，核当前preset和引擎/template采用版本，不擅自安装、升级或添加其他平台发布流程。

- 先确认这是当前源码、当前成品还是明确保留的历史P5包；路径/标签准确，避免重导覆盖历史包或将旧包说成当前游戏分支。历史试玩继续用自己的存档目录/格式。
- 源码里能读不代表包里有。检查原生资源依赖、动态路径加载、非Resource数据如JSON的export include/filter、忽略目录与大小写；移动资源保UID与真实引用。新增数据必须在导出包内实际被读取，不能只看导出退出码。
- 用DirAccess列举`res://`资源时核导出重映射，不能依赖编辑器中可见的原始文件名/扩展。需要资源列表时按目标版本使用`ResourceLoader.list_directory()`或既有显式目录，读取纯文本/JSON仍用FileAccess；不能一律将非资源文件改成ResourceLoader加载。
- 发布后的`res://`只读，世界存档和偏好写原`user://`入口。更改项目名或custom_user_dir会改变数据位置，核既有用户数据策略，不通过删档让包“启动成功”。
- debug/release、headless/窗口和是否内嵌PCK影响行为与证据。模板版本匹配当前引擎；若无模板如实报告，不能用编辑器运行截图冒充独立包验证。
- 导出后从不依赖源码目录的交付目录冷启动，核入口、动态数据、关键界面及本次相关行为；涉及存读再用独立档验证退出重启。包内资源读核和原生GUI玩法是不同证据，不默认重做全部长测。
- 交付记录源码commit、EXE/PCK对应关系与实际验证范围；若工作区未提交，标明差异，不仅写“最新版”。构建产物/日志不入Git，入口菜单与成品状态沿原位置维护。

Web/手机/签名/加密按用户实际平台目标另查，不恢复与PC无关的长检查表；包内加密不能存真正机密。

官方依据：[导出项目](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html)、[命令行](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)。
