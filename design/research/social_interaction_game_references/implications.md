# 社会交互游戏研究：信息、承认、职位与执行：场景、建议与来源

> 研究资料：记录来源与适用限制，不授予引入依赖或改变规则的权限。

> 研究与来源记录：参考与建议不自动成为游戏规则或依赖。

## 用“闭关百年”场景检验研究结果

以下完全是对 Reol 的设计推论，不是任何参考游戏的现成功能。

| 社会事实或利益 | 原先由什么支撑 | 换掌门后可能怎样 | 玩家可以做什么 |
|---|---|---|---|
| 与老掌门的私人友情 | 双方共同经历 | 当事人死亡，不能再亲自帮忙；其他人的记忆可保留 | 拜访旧识、寻找原有见证 |
| 礼貌与尊称 | 辈分、历史、畏惧、当地规范、在场者 | 守礼仍有理由，公开支持却未必存在 | 观察私下与公开行为差别 |
| 自由出入某秘境 | 旧掌门的口头照顾、凭证或正式授权 | 可能过期、被撤销、仍有效或执行者不知情 | 出示凭证、找负责人核验、另求担保 |
| 宗门已登记贡献 | 功德堂账目、发行权限、见证、门规 | 不必随私人友情消失；可能出现争议、冻结或继续正常兑付 | 查账、补证、申诉、谈条件 |
| 库房实际兑付 | 库存、拨付权限、库管行动 | 账认了也可能缺货；有货也可能被阻挠 | 换货、延期、寻找新的执行支持 |
| 对弟子的影响力 | 弟子各自的认识、利益、职责与风险 | 旧人、新人和不同派系不必一致 | 说服具体人，改变具体问题的条件 |

重要修正：这个场景不宜写成“老掌门死亡→所有旧账打折”。私人恩惠、公账债务、正式授权和当众礼数有不同的延续条件。只有拆开这些来源，玩家才有调查、争取和反制的空间。

## 对交互框架的初步建议

这些是候选讨论的骨架，尚未定稿。

1. **发生的事、个人所知、机构记录、认可决定、实际执行分别表达。** 存储可以集中，语义上的保管者与权限必须清楚；不需要给每个 NPC 建一套数据库。
2. **交互是一个有后续的流程。** 目标或事件产生请求，参与者各自评估，形成承诺，进入实际行动；知情者再解释结果，影响下一次选择。答应、做到、被记账、被认账、拿到好处不是一个步骤。
3. **人物与机构都通过具体行动产生影响。** NPC 也能申请、担保、拒绝、隐瞒或追责；玩家缺席时，规则仍应运转。职位规定谁能签署，任职者决定如何运用权限，其他人负责或拒绝执行。
4. **关系允许互相矛盾的判断共存。** 喜欢某人、相信其能力、相信其守信、欠其人情、怕其报复可以不一致；公开礼貌还取决于听众与规范。
5. **数值各有含义和来源。** 物资是数量，贡献是有发行与兑付规则的制度记录，信任是某人根据经历形成的预期。可以缓存摘要，但重要决定应保留主要依据。
6. **骰判处理选择的不确定性。** 先检查资源、权限和已知情境，再评估行动；骰子不能造出库存或合法凭证。人物可以违规，违规仍须通过实际行动并承担发现与追责风险。处境没变时，不靠重复点击反复抽结果。
7. **用有限的重要事件支持长期历史。** 保留有效授权、未结义务、重要经历与证据来源；普通生活逐渐汇总。百年跳时需要单独设计人口、制度、记录和资源的演变，不能只让好感统一衰减。

“代币”的比喻很适合解释某种贡献凭证的认可范围与兑付能力；友情、忠诚、师徒义务则可能无法自由转让或互相兑换。Claim 可用于可登记的权利、义务与主张，不适合强行包办所有心理和人际关系。

## 后续可选研究问题

最终框架需要说明：基本对象及其归属、交互流程、NPC 决策输入、消息传播、职位与权限、记录与争议、执行与资源、长期演化，以及玩家如何获知原因。

建议先用三组场景检验同一套规则，而后确定数据结构与概率：

- **普通合作**：受伤弟子求药，同伴担保或代工；区分没能力与故意失约。
- **信息分歧**：账页损毁、两名见证人说法不同；区分真相、相信与官方裁定。
- **权力更替**：老掌门死亡；区别私人方便、公账权利、公开礼数与实际兑付。

每组都要能由 NPC 自主发起；改变一个关键事实应改变具体回应；失败后仍有后续行动；主要原因能通过游戏内信息逐步理解。这些才是后续验收方向，不预先固定旧继任算法的权重。

## 来源

- [E1] Eco，2020 年官方日志：[Elections and Elected Titles / Work Parties](https://store.steampowered.com/news/posts/?appids=382310&enddate=1584894578&feed=steam_community_announcements)。聚合页内定位 2020-02-29 与 2020-03-17。
- [E2] Eco，官方技术文档：[BankAccount](https://docs.play.eco/api/server/eco.gameplay/Eco.Gameplay.Economy.BankAccount.html)。参见账户类型、权限与国库管理说明。
- [V1] EVE，官方支持：[Roles Listing](https://support.eveonline.com/hc/en-us/articles/203217712-Roles-Listing)。
- [V2] EVE，官方支持：[Access Lists](https://support.eveonline.com/hc/en-us/articles/208289645-Access-Lists)。
- [V3] EVE，官方支持：[CEO and Directors](https://support.eveonline.com/hc/en-us/articles/203279841-CEO-and-Directors)。
- [V4] EVE，官方支持：[Corp Theft](https://support.eveonline.com/hc/en-us/articles/203269541-Corp-Theft)。
- [C1] CK3，官方：[Dev Diary #137: Machinations of a Clan](https://store.steampowered.com/news/posts/?appids=1158310&enddate=1698148834&feed=steam_community_announcements)，2023-10-17，Tax Jurisdictions and Tax Collectors。聚合页内定位标题。
- [G1] The Guild 2：[官方手册 PDF](https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/39650/manuals/Guild2_Manual.pdf?t=1727858290)，Favour / Politics & Court / Crime & Evidence / Gathering Evidence / Court Proceedings。
- [D1] Dwarf Fortress：[2014 官方开发日志](https://www.bay12games.com/dwarves/dev_2014.html)，2014-02-24。
- [D2] Dwarf Fortress：[2019 官方开发日志](https://www.bay12games.com/dwarves/dev_2019.html)，2019-11-13、11-21、12-05。
- [P1] McCoy 等，2014：[Social Story Worlds With Comme il Faut](https://cs.uky.edu/~sgware/reading/papers/mccoy2014cif.pdf)。
- [B1] Evans、Short，2014：[Versu 作者论文](https://versu.com/wp-content/uploads/2014/05/versu.pdf)。
- [B2] Versu，2014-06-12：[Blood & Laurels 发行公告](https://versu.com/2014/06/12/blood-laurels-now-in-the-app-store/)。
- [T1] Ryan、Mateas，2017：[Simulating Character Knowledge Phenomena in Talk of the Town](https://www.gameaipro.com/GameAIPro3/GameAIPro3_Chapter37_Simulating_Character_Knowledge_Phenomena_in_Talk_of_the_Town.pdf)，Game AI Pro 3，第 37 章。
- [T2] James Ryan：[作者项目档案](https://jamesryan.computer/)，Bad News 项目介绍。
- [K1] David Dunham，2013-12-31：[Friends and Relations](https://kingofdragonpass.blogspot.com/2013/12/friends-and-relations.html)。
- [R1] RimWorld：[Ideology 官方介绍](https://rimworldgame.com/index.php/ideology)。
- [N1] Lo-Fi Games，2018-08-16：[Kenshi 开发日志：World states](https://lofigames.com/blog-25-kenshi-at-tokyo-game-show/)。
- [S1] Shadows of Doubt：[开发商商店介绍](https://store.steampowered.com/app/986130/Shadows_of_Doubt/)。
- [S2] ColePowered，2025：[Devblog #44: Modifiers Update](https://colepowered.com/shadows-of-doubt-devblog-44-modifiers-update/)。
- [M1] TaleWorlds：[Dev Blog 05/12/19 / Kingdom Decisions](https://store.steampowered.com/news/posts/?appids=261550&enddate=1582150590)，聚合页内定位 2019-12-05。
