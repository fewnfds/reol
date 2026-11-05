# Reol 完整游戏长期开发方案：5. 玩法总图与内容负责人

> 历史长期产品规划：阶段编号、Goal、当时状态和下一步均为成文时的建议，不是当前工作队列或实现证据。当前优先级见[基础优先级](../../foundation-priorities.md)。

## 5. 玩法总图与内容负责人

```text
生态/地理 → 采集/农业 → 生产/库存 → 市场/运输 → 日常生活/修炼/建设
                              ↓                      ↓
                      工资/税费/贡献/凭据       组织依赖/竞争
                              ↓                      ↓
                    职位/授权/关系/消息 ← 争端/冒险/战斗
                              ↓                      ↓
                        身份变化/继任 ← 伤亡/迁居/历史
```

- [玩法目标](../../../../design/systems/playable_world_target.md)：每种玩法如何操作、失败和接续。
- [世界模拟目标](../../../../design/systems/world_simulation_target.md)：事实、时间、跨层、物资、战争、历史与规模契约。
- [参考与素材研究](../../../../design/research/full_game_reference_map.md)：哪些机制可借鉴、哪些是推断、素材许可与制作路线。
- [验收矩阵](../acceptance.md)：怎样证明整个游戏成立，而不只是各个函数能跑。
- [首工作包](../../../archive/specifications/world_foundation.md)：下一次实际实施的起点。
- [人物与战斗详细设计](../../../../design/proposals/combat-and-characters.md)：动作规则、纸娃娃与社会外观、无职业修行网络及C0–C7主题拆包。
- [最新世界总纲](../../../../design/systems/self_consistent_world.md)与[世界先行工作包](../multiple-lives.md)：共同世界、多种生命、知识/法器/创造与W0–W7样本；修订完整铺建造/战斗内容之前的验证顺序。
- [资源与工具搜集工作包](../../../archive/specifications/resource_tooling_scout.md)：原调研Goal的资源范围、候选决策和接续记录；[本机审计](../../../engineering/tooling/resources.md)记录当时配置与连接证据，当前配置见[套件实装](../../../engineering/tooling/setup.md)。

现有 `living_world_framework`、`world_continuity`、`settlement_services` 继续负责已有规则；新目标文件只补长期方向。原继任权重保持提议状态，后续依据场景校准，不能靠沿用旧数字宣称政治设计已完成。
