# 完整游戏的参考取舍与素材路线：素材与代码生成

> 重建说明（2026-11-12）：本页引用的旧代码起点已退役，历史链接固定到重建前提交；它们不是现行实现。当前状态查[工程入口](../../../docs/engineering/README.md)。


> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

> 研究与来源记录：参考与建议不自动成为游戏规则或依赖。

## 素材：先把用途与权限弄清楚

“免费”“开源”“允许商业使用”是不同判断。代码仓库的 MIT/GPL 文件不自动覆盖仓库中的贴图、音乐、字体、商标或从别处引入的素材。商业参考游戏用于理解机制，其贴图、角色、音效、名称和标志不属于可直接借用的开源素材。

下表是候选来源，**未下载、未导入、未最终选型**。页面许可信息支持初筛；真正引入时必须核对下载包中的文件和许可。

| 候选 | 本轮核实与拟用途 | 使用条件与选择 |
|---|---|---|
| [Kenney Tiny Town](https://kenney.nl/assets/tiny-town)、[Kenney 支持说明](https://kenney.nl/support) | 官方页面标为 CC0；适合初期地表、房屋和道具的样例 | CC0 可商用和改作；仍保存包内许可证。现成包不必作为最终国风方向，避免和代码人物产生比例冲突 |
| Screaming Brain Studios：[Top Down Dungeon Pack](https://opengameart.org/content/top-down-dungeon-pack)、[作者下载说明](https://screamingbrainstudios.com/downloads/) | 具体 OGA 条目标为 CC0；作者说明素材包为 CC0。可用于洞府/遗迹占位 | 选择正交俯视版本，核对尺寸和视角；不因为同作者就忽略实际文件内容和包内说明 |
| [Whispers of Avalon: Grassland Tileset](https://opengameart.org/content/whispers-of-avalon-grassland-tileset) | OGA 条目列有 CC BY 3.0 等选择；是“非 CC0 仍可能可商用”的具体例子 | 若选 CC BY 3.0 路径，按作者、标题、来源、许可链接和修改记录署名，并检查分发条件；不是推荐直接混搭的最终包 |
| [Universal LPC Character Generator](https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator)、[许可与署名说明](https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/master/README.md) | 可组合身体、服装和动画；README 明确不同部件对应 CC0、CC BY、CC BY-SA、OGA BY、GPL 等许可，提供导出署名表 | 不把 LPC 当统一 CC0 包；按实际部件选择可兼容许可并导出完整来源。若改色/拼装后的义务不清，先用自制人物替代，不把整个生成器作为运行依赖 |
| [Noto Sans CJK 字体许可](https://raw.githubusercontent.com/notofonts/noto-cjk/main/Sans/LICENSE) | SIL OFL 1.1 允许按条件与软件打包；候选用于中文 UI | 具体字重/发行版逐文件核对，保留版权和 OFL；子集化/修改时检查保留字体名；不把机器上的系统字体直接拷入发布包 |

许可原文入口：[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)、[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)、[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)、[CC 官方 FAQ](https://creativecommons.org/faq/)。它们说明可商用范围及条件；不能从“可商用”推导出“不需要署名、可施加任意限制、可任意更换许可证”。CC BY-SA/GPL 不是不能商用，但引入之前需要评估改作、再分发和分发平台条件，不列为默认省事路线。NC、ND、来源不明或授权链不清的素材不用于计划中的可修改商业资源库。

音乐、环境声和音效也逐项登记。编曲授权、录音授权、音源授权不能互相代替。字体、音频和界面图标不因体积小而豁免来源记录。

## 适用边界

实际采用清单、来源记录与重建入口统一见[assets](../../../assets/README.md)和[第三方声明](../../../THIRD_PARTY_NOTICES.md)，不在研究页维护第二套引入表或审批步骤。这里的“未下载”指2026-11-02调查时点，后续选型不持续回写历史候选状态。

先做少量可读样本再批量扩展，是可选制作策略，不要求先完成全部玩法或一整套验收表才能换素材。图像尺寸、锚点和动画应与真实占地/行动相容；表现不成为第二份库存、身体或命中事实。当前实现查[架构](../../../docs/engineering/architecture.md)，旧画布类与阶段清单由[Git](https://github.com/fewnfds/reol/blob/02958cc/design/research/full_game_reference_map/assets.md)追溯。

## 来源核查边界

本轮完整打开并阅读了 RimWorld 官网、DF 官方特性、Kenshi 官方介绍及 World states 日志、两款修仙游戏的官方商店正文、WH3 官方商店正文、Rome II 官方手册、Bannerlord 官方商店、Qud 官网、Against the Storm 的开发日志、Screaming Brain Studios 作者下载页、LPC README、CC0/CC BY 许可摘要以及 Noto Sans CJK 许可原文。

Kenney、OGA 具体条目及 Bannerlord 两篇日志的直接抓取分别遇到访问限制/403；本轮核对了搜索服务返回的官方域名索引摘要和明确许可/标题，未读取下载包、未核查包内许可。条目只作为候选；引入时仍要补实际文件验证。Starsector 官方经济日志抓取返回 402，未把第三方转述写成已核实的一手实现，不作为本轮主要取舍依据。

以上是一次有边界的方案研究，不能代替在 Reol 中实现、试玩、压力测试和授权文件复核。
