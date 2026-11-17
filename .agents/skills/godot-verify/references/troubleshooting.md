# Godot 验证排错要点

<!-- Includes adapted headless guidance from awesome-gamedev-agent-skills (Apache-2.0); modified and merged for Reol on 2026-11-17. See ../../../../THIRD_PARTY_NOTICES.md. -->

- 先检查实际目标引擎和项目路径，再读第一条解析或运行错误及对应行；后续错误可能是级联。新检出、资源变动或 `class_name` 不可见时按需做无头导入。
- `push_error`和脚本运行错误不保证进程非零退出；SceneTree检查显式汇总成功/失败并`quit(1)`，runner核返回值与错误输出，不能只认进程结束或打印通过数。裸`assert`可能中断到`quit`之前，使检查挂起。
- `SceneTree._initialize()`早于autoload和场景ready。依赖它们的检查延后启动；同步runner不会自动等到异步检查尾部，显式等待并有失败退出路径。
- 编辑器内的脚本/预加载缓存可能滞后于文件变动；用新导入、独立进程或实际返回的诊断状态核对，不把旧编辑器日志直接当本次结果。不要清除用户日志来制造干净证据。
- 收集stdout/stderr，在原短超时内完成；超时是失败信号，先定位等待/退出错误，不反复延长时限或靠轮询日志判断通过。导入仅在缓存/资源可见性需要时运行，不每轮重做。
- 场景与交互验证要确认项目、场景、窗口、运行状态和实际输入，再查看相关日志及原生画面；空截图、旧帧或只返回 `ok` 都不是功能成功证据。
- 迁移和存档回归使用只读历史 fixture 或副本，核对源文件未被覆盖；记录实际验证版本、范围、输出和未解决问题。
