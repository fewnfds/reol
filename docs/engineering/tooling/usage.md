# 工具入口

采用版本见[BASELINE](../../status/baseline.md)，配置见[实装](setup.md)。旧CI、全量check、分片、覆盖聚合与自动审查流程已退役，当前开发方法见[性能开发](../workflow/testing.md)。

## 常用命令

```powershell
python tools/godot.py doctor
python tools/godot.py import
python tools/godot.py test
python tools/godot.py test --suite actor_batch
python tools/godot.py run
python tools/godot.py editor
```

`test`仅跑三个最小smoke，默认15秒，不自动导入。新检出、新class或资源不可识别时才需要import。`check`及旧`--shard/--jobs/--test-timeout/--timing-report`参数已移除，不保留指向旧体系的别名。日志实时合流落盘，错误和超时返回非零；普通run/editor不会因错误行强关用户窗口。

## 实际性能

```powershell
python tools/stress_demo.py --residents 150 --seconds 20 --quit-after-capture
python tools/diagnose_demo.py --seconds 30 --auto-start --quit-after-capture
```

压力入口两地各150人，持续使用普通Main原人物、寻路、生活、环境及共同时间；临时人口状态不写玩家档。`--actor-workers 0`与默认4可对照同一Packed数学的串行/线程执行，不能预设后者更快。普通诊断保留原开局；不加`--quit-after-capture`可继续试玩。

结果在忽略的`logs/crowd-*`或`logs/demo-profile-*` JSON及JSONL。记录实际世界流速、帧时、结算步骤、批计算准备/采用等；测量本身有开销，单次差异不足以证明收益。先读已测最大成本，保持内容、人数、命令和采样窗口可比。headless只证明CPU/工具路径，画面性能用真实显卡渲染。

实现仍在`tools/diagnostics/demo_recorder.gd`及两个`tools/qa/`开发入口，普通Main不加载诊断器。HUD常显FPS、帧间隔和世界流速，F3展开详情。Godot编辑器Debugger → Profiler/Visual Profiler用于继续定位；宿主帧间隔不能冒称GPU时间。

## 其他工具

- `python tests/tool_smoke.py`：几秒内核对启动器的错误/超时退出，仅在修改启动器时需要。
- `python tools/check_structure.py`：可选的链接/字面路径检查，不是提交门禁。
- `python tools/setup_codex.py --check`：配置发生问题时核对项目条目，不证明MCP握手；不必每包执行。
- Godot AI负责实时场景/输入/截图，使用官方dock Configure生成认证attach，操作前确认项目与实际会话。Context7查目标版本API；不手改第三方addon或用裸HTTP绕过连接。

手动代码审查按实际需要使用原生review，沿用现有项目路由与配置；不调整全局模型/权限，不启用云端模型审查或后台CI等待。独立导出仍需实际模板/预设和运行证据，不能把命令存在当作已发布。
