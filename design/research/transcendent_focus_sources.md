# 修仙、战略与人生模拟：玩法重心和远区参照

研究日期：2026-11-03；对应[超凡者优先方案](../../docs/archive/specifications/transcendent_focus.md)。实际打开一手页面，区分开发者功能说明、特定版本实现记录和对Reol的推论。未试玩这些作品来核验全部宣称，不据用户标签/评论推断内部架构。

| 来源 | 核实到的侧重点 | 对Reol的取舍 |
|---|---|---|
| [鬼谷八荒·开发者商店说明](https://store.steampowered.com/app/1468810/?l=schinese) | 修为/境界、功法组合、妖兽与秘境、宗门身份和争夺；秘籍与世界活动相连 | 让修行、探索、战斗和组织共享价值链；不据“NPC生态”宣传证明其社会模拟深度 |
| [觅长生·开发者商店说明](https://store.steampowered.com/app/1189490/?l=schinese) | 五行灵气支付神通，功法/大道/法宝搭配，闭关、学习、寿元与奇遇 | 修炼选择影响能力与人生时间；不能把所有过程退化成等待条和材料检查 |
| [太吾绘卷·开发者商店说明](https://store.steampowered.com/app/838350/?l=schinese) | 功法技艺、人际/门派与传承，距离和功法配合的战斗 | 能力网络连接来源、关系、理解与实践，不只是花点数；内容数量不能证明组合质量 |
| [Bannerlord·发行商商店说明](https://store.steampowered.com/app/261550/?l=english) | 个人战斗、同伴/部队、战略世界、氏族与政治相接 | “侠客→领袖”可体现为行动规模和影响关系的变化，不锁定为固定职业；不同尺度共享损失和战果 |
| [Battle Brothers·功能](https://battlebrothersgame.com/features/) | 装备决定可用动作，背景、特质和发展塑造没有固定职业的战士，合同连接旅途与战术战斗 | 武器/法器应改变玩法；强经济压力也可能把玩家推向重复赚钱，需要控制 |
| [Battle Brothers·战略世界](https://battlebrothersgame.com/strategic-worldmap/) | 派系拥有目标与资源，商队受袭等世界变化形成合同需求；页面标明部分当时已实现 | 学“实际问题→委托→介入→地方后果”；页面含早期版本，不把旧案例当当前精确算法 |
| [The Sims 4·目标设计说明](https://www.ea.com/games/the-sims/the-sims-4/news/whims-aspirations-goals) | 愿望、可更换的抱负与奖励特质帮助玩家找到生活方向 | 可给人物目的/机缘线索，保留多路径；不把清单当全部动机。文章为2014年说明，旧Whims不是当前系统承诺 |
| [Path of Exile·官方概览](https://www.pathofexile.com/game) | 共享被动网络、关键节点的规则变化/代价、技能和辅助组合 | 借网络与构筑深度，先有少量实际改变行为的连接；不先用千节点数字树替代师承和学习 |
| [X4·官方概览](https://www.egosoft.com/games/x4/info_en.php) | 持续经济与派系、玩家从个人活动扩展到舰队/设施经营 | 世界自主与玩家影响相互连接；产品说明不是内部算法披露 |
| [X4·官方托管3.xx更新日志](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Game%20Updates%20and%20Patch%20History/X4%20Foundations%203.xx%20Changelogs/?language=en) | 具体记录low-attention远战、远区弹药和舰队行为的改进 | 已发行作品也需要修正近远规则差异；可证明分精度，不能证明整个引擎只用事件 |
| [Dwarf Fortress·持续世界说明](https://bay12games.com/dwarves/features.html) | 同一世界的文明、人物和历史持续存在，可在后续局面继续体验 | 保留人物来源与历史；离开区域不等于销毁事实 |

前轮[成熟项目复核](../../docs/archive/report-entries/progress-and-architecture-review-20261103.md)中的CDDA长动作、OpenTTD命令入口、Veloren近远共享意图仍有价值。Veloren接口明确可能有损，不能据此放松Reol对唯一法器、具名人物、旧债和已发伤势的持续性要求。

综合判断：不同成功作品把预算集中于自己的决策核心。Reol应优先构建“修行与冒险改变能力，能力改变处理冲突的办法，结果改变个人关系与组织局势”。生产和环境负责提供来源、约束、地点与争夺理由，暂不扩为另一款完整农场模拟。

远区建议采用事件边界和稳定过程批算的组合；任务来自已有行动者的目的和问题。随机只能产生候选，真实事件仍需要人员、资源和地点；死亡、宝物和权力变化必须可接续。此为Reol的技术方案推论，不声称以上作品共享同一引擎实现。

Starsector官网此次访问返回402，没有用第三方Wiki或经验印象补写内部机制。DF的2022日志未找到稳定可用的官方归档URL，删除该具体日期的袭击算法细节，只保留可定位的持续世界功能说明。没有安装或复制任何来源的素材/代码。
