# 历史存档：HANDOFF（2026-11-02 目录整理前）

> 历史材料，不作为当前进度或开发指令。当前入口：[项目文档](../../README.md)。

# 交接摘要（重启对话用）

> **最新双聚落实现（2026-11-02）**：用户授权先做场景测试，C+“离场与归来”已接主场景：区域关键边界/批算、真实运粮、封路续行、延迟消息、玩家真实地形往返、入场接续和联合存读。`check` **37 组 / 1,082 断言 / 0 失败**；Python 7 条通过。先读[双聚落实现记录](../WORLD-CONTINUITY-IMPLEMENTATION.md)。下文“尚无区域算法/下一轮做 C+”已被取代。河湾访客服务、迁居、远区战斗和大型世界性能尚未完成；只验证小范围连续性。

> **当前入口（2026-11-02）**：世界模拟首个运行骨架已实现并验证，先读 `docs/LIVING-WORLD-IMPLEMENTATION.md`。34 组 / 753 断言绿色；下面较早的“未实现”“下一步删 contribution”等文字保留作历史，不要照此重做。
> **最新澄清**：用户强调离场后世界仍持续运转、返回时接续现场。“百年闭关”只是例子。当前 5 NPC 离屏仍 tick，但尚无区域卸载后的粗算与接续。下一轮优先做两聚落的 C+ 连续性验证，见 `design/systems/world_continuity.md`；不要再把它归为仅后期的长期跳时功能。本轮澄清仅更新设计与优先级，未实现远区算法。

> **2026-11-02 最新方向**：用户要求继续讨论社会架构与互动系统，重新审视此前 AI 归纳的约束。目标是由人物生活、动机、认知、关系和行为后果形成真实可信的社会循环，而非顶层数值加减驱动进度。下文的 Claim 中心方案、算法权重和“下一步”均为旧提案，不能当成已经确认的实施要求。当前尚在架构讨论，未批准新实现；见 `design/systems/social_system.md` 开头的评审前提。
> 用户允许内置骰判/概率判定，因素由助手参考心理学、社会学选择，同时保持游戏简洁。当前精简提案、边界与研究链接记录在 `design/systems/social_interaction_review.md`；具体权重与骰制未定。
> **同日追加说明**：目标是模拟网游/修真小说中的活社会。个人、组织与阵营评价分别形成；尊敬不等于实惠或卖命。NPC 各有打算与个性，门派和势力有目的及立足之本，内部成员可有分歧。以任意身份进入仍能获得生计、目标、义务、机会和冲突，作为世界真实性的检验；具体可选出身范围未因此定稿。用户说明名称：**reol = reroll**，源自 Dota Allstars 的 `/reroll`（重选英雄）。游戏机制比较见 `design/research/social_interaction_game_references.md`。
> **最新任务结果：总体计划提案**见 `design/systems/living_world_framework.md` / ADR-0022（提议）。六个职责：世界状态、人物行动、信息与关系、组织与制度、局势演化、玩家呈现。建议先做可推进状态、日常供给和 NPC 互助，再接正式账目、权限、局势与冒险，最后扩展继任和远区。信息边界与最小快照从第一阶段建立；当前只完成计划文档，未实现新框架。下文的旧实施顺序不再作为默认下一步。
> **最新实现优先于上条计划状态**：用户已授权实施，ADR-0022 的架构方向已接受。`scripts/sim/` 与 `data/scenarios/village.json` 已接主场景：NPC 需求/职责/执行、真实供给、请求与承诺、知识来源、有向关系、贡献账目、授权/晋升 API、可恢复在途行动、原子存读和操作面板。`PawnState.contribution/reputation` 已删除。`python tools/godot.py check` **34 组通过、753 断言、0 失败**；Python **7 条通过**；实际完成搬柴→报工→2贡献、按钮存读与1280×720截图检查。详情/后续：[实现记录](../LIVING-WORLD-IMPLEMENTATION.md)。继任演出、远区、百年闭关、完整世界存档仍未接入；不要把隔离的继任原型误当全社会系统。

> 日期：2026-11-02
> 用途：新会话冷启动时，代替翻完整聊天记录。读完这份 + `AGENTS.md` 就能继续。

---

## 1. 项目与硬约束

- **Reol**：Godot **4.7.2** / GDScript / 2D 正交俯视 / 正方形格 / 高度层。
- 修仙开放世界沙盒 + 宗门模拟 + RPG。参考：Dwarf Fortress 的模拟深度、RimWorld 的 NPC 管理、Kenshi 的沙盒、传统 RPG 的成长。
- 单机；不做联机、账号、服务器、C#、LLM 核心模拟。
- 首区 512×512，64×64 区块；实时 + 暂停；脚本 AI 优先。
- 当前目标：一个 45–60 分钟的 vertical slice（“一山一宗”），不是做完整游戏。

## 2. 已完成 / 进行中

### 已完成
- **M1**：俯视网格、相机、玩家移动、区块流式、高度层、战争迷雾、时间/暂停/倍速/昼夜、碰撞打磨。
- **M2 数据层**：`data/definitions/origins.json`、`ranks.json`、`pawns.json`；`ReolContentDB` 加载与引用校验；`PawnState`；玩家 + 5 个具名 NPC（陈守拙、阿禾、石头、苏芷、老周）；点击选中面板。
- **社会系统设计**：`design/systems/social_system.md`（五层模型、Claim、账本、职位、继任、UI、扩展性）。
- **继任算法原型**：`scripts/social/succession_resolver.gd`，纯函数，两阶段，可覆盖权重。
- **ADR**：ADR-0020（社会事实 = Claim）、ADR-0021（两阶段继任算法），状态均为“提议”。
- **测试**：`python tools/godot.py check` → **28 passed / 0 failed**；其中继任算法 10 条。
- **提交**：`f05b317 feat: add algorithmic succession resolver and design`。
- 工作区仅剩生成文件 `scripts/social/succession_resolver.gd.uid` 未跟踪（可忽略/加入 ignore）。

### 未完成（下一步）
- `ClaimBook` / `Office` / `Institution` 最小数据结构。
- 删除 `PawnState.contribution`，贡献改为账本派生视图。
- 老掌门、新掌门加入 `pawns.json`；把继任算法接进 `main.gd` 的“老掌门坐化”事件。
- HUD 显示“账面 / 私记 / 传闻”三列 + 2–3 句人话理由。
- `JobBoard` 完成差事时调用 `SocialAPI.issue_claim(...)`，不再直接加贡献。
- 存档：先存 Claim/关系/职位快照。

## 3. 社会系统的核心结论（最重要）

### 3.1 基本立场
**社会事实不是人物属性，而是机构账本里的记录。**

- 贡献由功德堂记账；人情由个人记忆；名声由传闻；面子由礼数。
- 同一个“社会事实”可以**面子还在、实利没了**。单一 reputation 数值表达不了这个。
- 人物可以记私账，但**私账不具官方效力**；官方账由机构、职位、法器发行/背书。
- **职位与人分离**：掌门签的账是公账，张三签的账是私账；换人后旧账可能被认、冻、折、赖。
- 内部数值化，外部只给定性词、账页、对话、通行、价格；**不做 Excel 式社交 UI**。

### 3.2 五层模型
1. **物质层**：资源、身体、需求。
2. **关系层**：信任、亲近、敬重、畏惧、亏欠（有方向、会衰减、按事件更新）。
3. **制度层**：机构、职位、规则、派系、程序。
4. **记录层**：Claim、账本、凭证、见证人、先例。
5. **叙事层**：传闻、官方历史、名声、合法性。

### 3.3 Claim 模型
一条 Claim 至少包含：

- `issuer`（发行方：机构/职位/个人/法器）
- `registrar`（记账人）
- `subject`（受益人/负债人）
- `scope`（适用范围：某个宗门/某座山门/某个秘境）
- `type`（v1：贡献 / 人情 / 见证）
- `amount` 或定性面额
- `status`（ACTIVE / FROZEN / REPUDIATED / SETTLED / DISPUTED…）
- `evidence`（账页、印章、批红、法器记录、见证人、私记、传闻）
- `provenance`（来源链、是否转让过）
- `validity` 不是布尔值，而是按 scope 分别成立。

关键规则：

- 没有无发行方的 Claim；没有无机构的职位。
- 状态转换必须合法；兑付不能重复；转让要守恒。
- 争议顺序：调解 → 审计 → 审判 → 私斗/暗杀/政变。
- 判决会形成**先例**，先例本身也是一种 Claim。

### 3.4 继任：两阶段效用算法（ADR-0021）

**阶段 A：谁继位，以什么合法性继位。**

候选人先过硬门槛（职位章程、血脉、境界、长老会推举、法器认可），再按八项加权：

```text
名分 0.25 · 派系 0.20 · 实力 0.18 · 控制 0.14
声望 0.08 · 财力 0.06 · 前任 0.05 · 外援 0.04
```

- 最高分继位。
- 相对差距 `(第一 − 第二) / 第一 < 0.15`：争议继位，合法性 ×0.8，第二名成为“未解决的竞争者”。
- 无人合格：空位期，旧账全部冻结。
- `legitimacy = clamp(0.60×S(winner) + 0.25×backing + 0.15×predecessor, 0, 1)`
- `insecurity = 1 − legitimacy`，直接进入阶段 B。

**阶段 B：逐笔旧账怎么处理。**

五个动作：`全认 honor / 折价 discount / 冻结 freeze / 谈判 bargain / 拒付 repudiate`。

十二个因素（全部 0..1）：

| 因素 | 含义 |
|---|---|
| validity | 凭证效力 |
| burden | 财政负担 |
| continuity | 认账换来的稳定/信用/人心 |
| affinity | 政治亲疏 |
| bond | 个人恩怨 |
| leverage | 持有人的反制能力 |
| visibility | 公开度 |
| precedent | 先例压力 |
| need | 新掌门对此人的需求 |
| old_regime | 旧朝关联 |
| insecurity | 不安全感 |
| legitimacy | 合法性 |

首版权重（已写进代码，数据可覆盖）：

| 因素 | 全认 | 折价 | 冻结 | 谈判 | 拒付 |
|---|---:|---:|---:|---:|---:|
| validity | +0.32 | +0.22 | +0.03 | +0.14 | −0.40 |
| burden | −0.30 | +0.12 | +0.18 | −0.06 | +0.30 |
| continuity | +0.18 | +0.10 | −0.06 | +0.08 | −0.20 |
| affinity | +0.08 | +0.04 | −0.05 | +0.06 | −0.10 |
| bond | +0.08 | +0.03 | −0.04 | +0.04 | −0.09 |
| leverage | −0.08 | −0.03 | −0.10 | +0.16 | −0.24 |
| visibility | +0.06 | −0.03 | −0.04 | +0.03 | −0.16 |
| precedent | −0.10 | −0.04 | −0.05 | 0 | +0.08 |
| need | +0.05 | +0.02 | +0.04 | +0.12 | −0.10 |
| old_regime | −0.10 | −0.10 | +0.14 | −0.02 | +0.08 |
| insecurity | −0.08 | −0.04 | +0.18 | +0.04 | −0.10 |
| legitimacy | +0.10 | +0.02 | −0.06 | +0.04 | +0.12 |

**硬门槛**（先于打分）：

- `validity < 0.20`：不能全认/折价/谈判。
- `burden ≥ 0.90`：不能全认。
- `leverage ≥ 0.75 && visibility ≥ 0.60`：不能拒付。
- `insecurity ≥ 0.65 && visibility ≥ 0.70`：不能拒付。
- `sealed_artifact && validity ≥ 0.70`：不能拒付。
- `expired` 且无 `renewal_clause`：不能全认。
- 人情账相对方死亡：默认失效；有遗嘱/信物/见证人则转成对继承人的 Claim。

**折价率**（不是固定 80%）：

```text
clamp(0.20 + 0.45×validity + 0.20×continuity + 0.15×(1−burden), 0.15, 0.90)
```

**性格偏差**（小幅，不覆盖制度理性）：重诺、多疑、务实、贪利、好名、记仇、软弱、果决。

**输出**：动作 + 折价率 + 前 3 个理由标签（如 `treasury_strained`、`weak_mandate`、`old_regime_loyalty`、`claim_well_evidenced`、`retaliation_risk`、`precedent_flood`、`personal_grudge`、`needs_support`）。UI 翻成人话，不显示分数。

### 3.5 关键认识：输入是“感知”，不是真相
新掌门可能低估你的实力、错判账目真伪、被派系蒙蔽、不知道你和前任的私交。调用方传入的是**他认为的值**。所以玩家觉得“应该全认”、结果被冻结，不是 bug，是信息不对称。

### 3.6 玩家应对（同一算法的不同输入）
- 找见证人 → 提高 `validity`。
- 请陈守拙担保 → 提高 `need` / `affinity`。
- 拿私记对质 → 单独只小幅提高 `validity`；有印章/法器/见证人时提升更大。
- 谈判 → 旧账部分恢复 + 产生义务 Claim，违约再起争议。
- 折价卖黑市 → 按宗门信用和凭证强度报价，**不是固定 40%**。
- 公开闹大 → 提高 `visibility`，可能逼出谈判，也可能被逐。
- 转投他宗 → 旧账作废，带走人情/技能。

### 3.7 已明确删除的旧设计
- ❌ `PawnState.contribution`（贡献不是人物属性）。
- ❌ 固定“恢复 80%”。
- ❌ 默认“冻结 + 重新登记”作为全局政策。
- ❌ 黑市固定 40%。
- ❌ 全局 reputation 条 / 阵营好感条。
- ❌ 把机构当铁板一块（机构态度 = 官方政策 × 派系 × 成员私意 × 叙事 × 利益）。

## 4. 首版切片（v1）范围

- 1 个宗门、1 个山门聚落。
- 新增 2 个具名 NPC：**老掌门**（玩家旧交）、**新掌门**（老掌门的死对头师弟，得位不正、库房空）。
- 3 个机构/职位：功德堂（记账人陈守拙）、任务板、掌门。
- 3 种 Claim：贡献、人情、见证。
- 1 次继任事件：老掌门坐化。
- 基线局面：新掌门合法性低、库房空、玩家无势力、旧账证据中等、公开度中等 → 算法输出**冻结**。
- 对照：名正言顺的师兄 + 库房足 + 玩家曾拥立 → **全认**；玩家强 + 法器封存旧账 → **谈判**。
- UI：三列认知面板（账面/私记/传闻）+ 账本页 + 对话语气 + 通行/价格变化。

## 5. 代码位置

| 文件 | 内容 |
|---|---|
| `scripts/social/succession_resolver.gd` | 两阶段纯函数；`resolve_candidates` / `resolve_claim` / `resolve_succession` / `apply_policy` |
| `tests/run_tests.gd` | 28 条测试，含 10 条继任测试 |
| `design/systems/social_system.md` | 社会系统全文；5.7 是继任算法 |
| `docs/DECISIONS.md` | ADR-0020、ADR-0021 |
| `docs/BASELINE.md` | 当前完成度、28 条测试 |
| `scripts/data/pawn_state.gd` | 仍含 `contribution`，待删 |
| `scripts/data/content_db.gd` | 待加 claims/institutions/offices 加载 |
| `data/definitions/pawns.json` | 待加老掌门/新掌门 |
| `scripts/main.gd` | 待接继任事件 |
| `scripts/ui/hud.gd` | 待改三列认知面板 |

## 6. 重启后的第一句话可以这样说

> 读 `docs/HANDOFF.md` 和 `AGENTS.md`。先不要改代码。确认两阶段继任算法与权重方向；然后从最小 `ClaimBook` / `Office` / `Institution` 开始，删除 `PawnState.contribution`。

## 7. 命令

```bash
python tools/godot.py doctor
python tools/godot.py check     # 导入 + 无头测试
python tools/godot.py run
```

当前预期：`28 passed, 0 failed`，`CHECK PASSED`。
