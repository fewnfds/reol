# 编辑器工具与技能

[运行与测量命令](usage.md)适用于普通检出，第三方组件版本与来源见[许可与说明](../../../THIRD_PARTY_NOTICES.md)。

- Godot AI 从编辑器配置认证连接，可以检查当前场景、运行状态、日志与截图。插件随项目保持完整，按实际项目和会话连接。
- 需要核对引擎 API 时使用所采用版本的官方文档。跨任务的开发约定见[项目约定](../../../AGENTS.md)。
- 本机助手及机器配置在开发机独立维护。

## skills怎样维护

项目在`.agents/skills/`维护按任务选择的领域入口，正文保留影响决策的检查，参考文件按问题查阅。

| 入口 | 使用范围 / 保留的专门知识 |
|---|---|
| [godot-sim-architecture](../../../.agents/skills/godot-sim-architecture/SKILL.md) | 模拟功能的owner、访问形状、跨步采用与恢复；接入原框架，避免套每NPC一个Node的教程 |
| [simulation-game-design](../../../.agents/skills/simulation-game-design/SKILL.md) | 跨系统经济/生态/社会玩法的处境取舍、反馈、低美术表达与实验；普通bug/微调/纯优化不触发 |
| [godot-verify](../../../.agents/skills/godot-verify/SKILL.md) | 相关短验证及headless导入、异步、错误退出/挂起排错 |
| [create-game-assets](../../../.agents/skills/create-game-assets/SKILL.md) | 纯二维斜俯视、脚点/图集接入；Pillow透明/尺寸/色数报告与联系表脚本 |
| [godot-gdscript](../../../.agents/skills/godot-gdscript/SKILL.md) | 类型/失败边界、Node与信号/await生命周期；按需资源引用检查器 |
| [godot-resources](../../../.agents/skills/godot-resources/SKILL.md) | 定义编译/校验、共享Resource与深层隔离、加载边界 |
| [godot-ui-input](../../../.agents/skills/godot-ui-input/SKILL.md) | Control布局、焦点/输入消费、按住/边沿与直接控制交接 |
| [godot-motion-navigation](../../../.agents/skills/godot-motion-navigation/SKILL.md) | 身体/脚点/坐标、连续碰撞、导航新鲜度与真实到达 |
| [godot-decision-systems](../../../.agents/skills/godot-decision-systems/SKILL.md) | 个人认识、效用/策略、Running/抢占及失败重试 |
| [colony-sim-systems](../../../.agents/skills/colony-sim-systems/SKILL.md) | 工作/工位、物资权属、原子转移和取消/恢复 |
| [godot-character-rules](../../../.agents/skills/godot-character-rules/SKILL.md) | 基础/派生数值、可逆来源、状态/装备/成长边界 |
| [save-systems](../../../.agents/skills/save-systems/SKILL.md) | 持久字段、独立候选恢复、格式边界、磁盘失败保护 |
| [godot-world-generation](../../../.agents/skills/godot-world-generation/SKILL.md) | seed/顺序、生成与持久变化、区块接续；按需TileMap检查 |
| [godot-2d-presentation](../../../.agents/skills/godot-2d-presentation/SKILL.md) | Camera2D、排序、动画/反馈、共同显示时间；按需shader/GPU检查 |
| [godot-audio](../../../.agents/skills/godot-audio/SKILL.md) | 现有战斗音频、voice限制、混音/音量与真实试听 |
| [godot-export](../../../.agents/skills/godot-export/SKILL.md) | Windows预设、非资源过滤、当前/历史包与独立冷启动 |
| [performance-optimization](../../../.agents/skills/performance-optimization/SKILL.md) | CPU/GPU/等待分诊、端到端成本、有效产出与同条件测量 |
| [level-design](../../../.agents/skills/level-design/SKILL.md) | 手工空间/开局的尺度、服务可用、可读性与真实试玩 |
| [dialogue-systems](../../../.agents/skills/dialogue-systems/SKILL.md) | 触及分支叙事时的会话/选择图/一次效果；不是当前已有剧情引擎 |

技能内的资源检查器覆盖资源 UID 和连线。`tools/check_structure.py` 检查项目入口、相对链接和静态引用。按当前改动选择，运行时效果由 Godot 验证。

## 更新或恢复时

先定位实际故障和所属组件，再核对兼容与许可，保存可恢复配置。按插件自己的流程更新整树或重新连到当前会话。验证与记录以实际调用和结果为准。
