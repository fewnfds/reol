# Design 文档

> `docs/` 是“项目怎么运转”；`design/` 是“游戏系统怎么运作”。
> 一个系统一个文档；先写清楚，再让 AI 实现。

---

## 什么时候写

- 新系统开工前（需求/工作/战斗/建造/任务/经济）。
- 改规则/数值前。
- 出现“这个行为到底应该怎样”的争论时。

## 不写什么

- 不写代码实现细节（放 `docs/ARCHITECTURE.md` 或技能）。
- 不写任务清单（放 `docs/ROADMAP.md`）。
- 不写营销文案。

---

## 文件命名

```
design/
├── systems/
│   ├── needs.md
│   ├── jobs.md
│   ├── stockpile.md
│   ├── building.md
│   ├── combat.md
│   └── save_load.md
├── content/
│   ├── items.md
│   ├── buildings.md
│   └── recipes.md
└── world/
    ├── biomes.md
    └── pois.md
```

- 全小写 `snake_case`。
- 一个文件一个系统。
- 新系统复制 `systems/_TEMPLATE.md`。

---

## 好设计文档的标准

- 一个新人能照着实现出 80%。
- 规则有优先级/边界/失败情况。
- 数值有单位/范围/默认值。
- 有“玩家会做什么决策”，不只是系统描述。
- 有验收场景（Given/When/Then）。
- 有“不做什么”。

---

## 和 AI 的配合

```
读 design/systems/jobs.md 和 docs/ARCHITECTURE.md 的 AI/工作章节。
先给实现计划（文件/信号/数据/测试），不要写代码。
我确认后再实现。
```

设计文档越清楚，AI 越少瞎编。
