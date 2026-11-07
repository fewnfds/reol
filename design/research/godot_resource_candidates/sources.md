# Godot 免费资源与插件候选评估：来源与版本许可

> 研究与来源记录：参考与建议不自动成为游戏规则或依赖。

## 1. 官方资源入口已经发生变化

| 入口 | 本轮确认的状态 | 使用方法 |
|---|---|---|
| [官方旧 Asset Library](https://godotengine.org/asset-library/asset) | [旧库文档](https://docs.godotengine.org/en/stable/community/asset_library/what_is_assetlib.html)说明其中资源免费、使用多种开源许可；不是统一 MIT | 查询老资源和原始仓库，不把搜索排名或“4.x”分类当 4.7.2 验证 |
| [官方 Asset Store](https://store.godotengine.org/) | [2026-05-22 官方公告](https://godotengine.org/article/introducing-the-godot-asset-store/)已宣布上线，称 live/stable 并集成到4.7；本轮官网首页和[当前文档](https://docs.godotengine.org/en/stable/community/asset_store/what_is_asset_store.html)仍显示 beta 提示 | 可以浏览真实条目及免费资源，不能再说“官方商店还没上线”；公告与页面成熟度表述不一致，保留这一边界 |
| 新旧库关系 | 上述公告把旧库视作 deprecated，并计划转为只读；文档说仍在线，内容不会自动迁移 | 不宣称本轮已验证旧库只读；找不到新条目时回原仓库核查，并固定实际版本 |
| 付费能力 | 5月公告把买卖列为后续事项；本轮只核查免费条目，没有测试结算 | 不把“Store”名字推导成已完整开放商业结算，不在本轮购买或登记付费账户 |
| 第三方 Marketplace/镜像 | `godotmarketplace.com`、`godotassetlibrary.com` 等名称不等于 Godot Foundation 官方 | 不从站名判断授权；回到官方域名、作者仓库和具体 LICENSE。前者页面还出现2026-10-30关闭说明，不作为长期依赖入口 |

官方商店上架是分发和审核信号，不是项目适配保证。通过 Context7 的 Godot 4.7 文档核对到：[提交要求](https://github.com/godotengine/godot-docs/blob/4.7/community/asset_store/submitting_to_asset_store.rst)要求资源在声明版本可运行且许可与仓库一致；这仍不代替我们对暂停、存档、远区批算和导出包的验收。

## 2. 推荐结论

目前不需要先安装一整套“游戏开发全家桶”。现有无头测试、数据定义、人物决策和相机都已经有实现；换成插件必须解决明确的问题，并计入迁移成本。

- **立即可用于阅读和设计比对**：官方 Demo 的相关小示例。复用前选具体项目与版本，不导入整库。
- **首次大量编写剧情时优先做隔离试验**：Dialogue Manager；已有生活/交易规则仍由模拟层执行。
- **测试框架只在现有 runner 明显不够用时二选一**：GUT 或 GdUnit4；不能为“更专业”重写现有全部测试。
- **局部 AI 的条件备选**：先比较小型自有 State Machine/效用判断与 Beehave；确需可视 Behavior Tree/HSM 和性能收益时再试 LimboAI。二者不能同时管理同一人物。
- **正式表现阶段按缺口选择**：Better Terrain、Phantom Camera、Kenney；已有可用相机与地表生成不必立即替换。
- **暂不引入主线**：Pandora 的 Alpha 数据库会与已有内容DB/存档争夺职责；Yarn GDScript 的预发布和特殊许可需要单独评估。

这是一组10项相关的可用候选，加1项应保留边界的 Yarn 对照；不表示全部都适合本项目当前阶段。

## 3. 版本、许可和维护证据

“作者声明兼容”列仅记录公开声明；没有任何一项标为“Reol 已验证兼容”。维护状况以明确发布或可见变更为证据，不按星数推断质量。

| 候选 | 本轮看到的版本/时间 | 许可证据 | 作者兼容声明与维护证据 | 推荐位置 |
|---|---|---|---|---|
| **GUT** | [v9.7.1](https://github.com/bitwes/Gut/releases/tag/v9.7.1)，2026-07-10；不是随意取main | [该版本 MIT](https://raw.githubusercontent.com/bitwes/Gut/v9.7.1/addons/gut/LICENSE.md) | [README版本表](https://raw.githubusercontent.com/bitwes/Gut/main/README.md)指定9.7.1对应Godot4.7.x；main当时仍对应4.6.x；该发布修复跨系统doubles问题 | 有测试发现/参数化/mock需求时，与GdUnit4择一 |
| **GdUnit4** | [v6.2.3](https://github.com/godot-gdunit-labs/gdUnit4/releases/tag/v6.2.3)，2026-11-02 | [该版本 MIT](https://raw.githubusercontent.com/godot-gdunit-labs/gdUnit4/v6.2.3/LICENSE) | [兼容表](https://raw.githubusercontent.com/godot-gdunit-labs/gdUnit4/master/README.md)列6.2.x支持4.7/4.7.1；未逐项列4.7.2。该发布修复4.7新编辑器字体问题、日志泄漏；master已面向7.0，不能拿master代替稳定版 | 需要场景输入测试、编辑器测试浏览/报告时再试 |
| **Dialogue Manager** | [v4.2.0](https://github.com/nathanhoad/godot_dialogue_manager/releases/tag/v4.2.0)，2026-10-30 | [该版本 MIT](https://raw.githubusercontent.com/nathanhoad/godot_dialogue_manager/v4.2.0/LICENSE) | 发布标题明确for Godot4.7；[README](https://raw.githubusercontent.com/nathanhoad/godot_dialogue_manager/main/README.md)写4.6+、无状态分支编辑/运行；近期修复非.NET项目导出夹带C#文件等 | 叙事内容生产优先候选 |
| **Beehave** | [v2.9.3](https://github.com/bitbrain/beehave/releases/tag/v2.9.3)，2026-08-18 | [该版本 MIT](https://raw.githubusercontent.com/bitbrain/beehave/v2.9.3/LICENSE) | 发布说明明确Godot4.7，修复4.7.1Singleton冲突、加载/卸载生命周期；纯GDScript Behavior Tree 路线。旧main教程与新Godot4分支不可混读 | 先做一个局部守卫/野兽行为试验，按需采用 |
| **LimboAI** | [v1.8.1](https://github.com/limbonaut/limboai/releases/tag/v1.8.1)，2026-08-20 | [该版本 MIT](https://raw.githubusercontent.com/limbonaut/limboai/v1.8.1/LICENSE.md) | [兼容表](https://raw.githubusercontent.com/limbonaut/limboai/master/README.md)区分GDExtension与引擎Module：1.8.x扩展4.6+、Module4.7；发布含4.7.2引擎构建。C++实现支持GDScript任务，不等于纯GDScript插件 | 复杂局部BT/HSM与可视调试确有收益时备选 |
| **Phantom Camera** | [v0.11.0.4](https://github.com/ramokz/phantom-camera/releases/tag/v0.11.0.4)，2026-10-28 | [该版本 MIT](https://raw.githubusercontent.com/ramokz/phantom-camera/v0.11.0.4/LICENSE) | [README](https://raw.githubusercontent.com/ramokz/phantom-camera/main/README.md)标4.4+；近期修复启用重启和Singleton守卫，前一补丁修复4.7.1Singleton注销问题 | 后期需要小队取景/镜头过渡时可选；现相机先保留 |
| **Better Terrain** | 无GitHub release；plugin.cfg版本为空。本轮远端HEAD为[`e93040e1cdd9dba0117c87f8f6b2883c83872d5d`](https://github.com/Portponky/better-terrain/commit/e93040e1cdd9dba0117c87f8f6b2883c83872d5d) | [固定提交 Unlicense](https://raw.githubusercontent.com/Portponky/better-terrain/e93040e1cdd9dba0117c87f8f6b2883c83872d5d/LICENSE.md)，不是MIT | [作者说明](https://github.com/Portponky/better-terrain)针对Godot4/TileMapLayer，多连接自动拼接。可见问题与PR，但未核最近提交日期，不能据此保证维护频率或4.7.2兼容 | 仅当原生地形拼接确有痛点再试 |
| **Pandora** | [v1.0-alpha10](https://github.com/bitbrain/pandora/releases/tag/v1.0-alpha10)，2026-07-28 | [该版本 MIT](https://raw.githubusercontent.com/bitbrain/pandora/v1.0-alpha10/LICENSE) | 发布称Godot4.7+和更早4.x，包含中文、唯一ID、数据迁移基础等修复；[README](https://raw.githubusercontent.com/bitbrain/pandora/main/README.md)仍明确Alpha、非生产就绪 | 数据编辑器研究，不替换现有权威数据/存档 |
| **Godot Demo Projects** | 不按统一插件版本；本轮远端master为[`b761b4cd5718a7118f2c95eb55f181d0a5f004f1`](https://github.com/godotengine/godot-demo-projects/commit/b761b4cd5718a7118f2c95eb55f181d0a5f004f1) | [固定提交 MIT](https://raw.githubusercontent.com/godotengine/godot-demo-projects/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/LICENSE.md)；具体Demo附带内容仍逐项读版权说明 | [README](https://raw.githubusercontent.com/godotengine/godot-demo-projects/master/README.md)明确master对应下一开发版、稳定分支按同名版本；本轮未找到4.7分支，不能编造可用4.7套件。官方仍在Store分发独立Demo | 按问题阅读；运行时先核具体Demo版本 |
| **Kenney Tiny Town 等基础包** | [Tiny Town官方条目](https://kenney.nl/assets/tiny-town)；本轮未取包，未核包内版本/哈希 | 官方条目标CC0，[作者支持说明](https://kenney.nl/support)说明资产页面资源为CC0 | 素材不绑定Godot API；本轮只有网页许可核对，不能把无版本资产说成“4.7.2已通过”。不是运行库维护问题 | 玩法清楚后用于基础地形/物件样板；看风格是否合适 |
| **Yarn Spinner for Godot GDScript（对照/暂缓）** | [v3.2.0-alpha8](https://github.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript/releases/tag/v3.2.0-alpha8)，2026-07-28；网页main已显示Early Access3.3，raw README缓存仍显示3.2 | [alpha8实际LICENSE.md](https://raw.githubusercontent.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript/v3.2.0-alpha8/LICENSE.md)为**YSPL1.0**，不是MIT，不归入宽松开源池 | 官方已有纯GDScript版，要求4.6+；[README](https://github.com/YarnSpinnerTool/YarnSpinner-Godot-GDScript)区分免费源码与付费支持/额外表现器。alpha说明有破坏性变化、当时不建议用其发布 | 不因C#旧印象误排除，但因成熟度、许可与已有替代暂不接入 |

YSPL的限制包含竞品工具用途/再分发和AI训练等，不能把“游戏可免费商用”写成“任意用途开源”。本轮仅阅读许可，没有复制实现；若将来要把它打包进开放项目或让其他工具加工，必须针对实际版本和分发方式评审。官方C# Yarn集成是另一个项目，不适合以引入.NET为代价迁移本项目。

上述版本是**核查候选**，并未写进工程依赖；以后采用时重新核查安全/兼容信息，固定通过验证的tag/commit与下载哈希。不能把版本号表当自动更新指令。
