# 构建、兼容与验证基线

核对：2026-11-05。这里记录采用版本与对应范围的证据；实际可操作内容见[功能入口](features.md)，任务状态和未提交工作见[接续](handoff.md)。旧的逐包原文已完整拆入[历史分卷](../qa/baseline-history/README.md)，具体测试和画面见[QA索引](../qa/README.md)。

## 采用版本与存档

- Godot **4.7.2 stable** 是这次采用和验证的版本；长期跟进最新稳定版，每次升级需核插件、CI与导出模板。当前是 GDScript、Windows 本机开发，CI 为 Linux 无头；Windows 正式独立包未验收。
- 当前普通联合根存档 schema **51**，区域 **42**、村落 **7**、热定义/状态 **3**、环境状态 **3**（climate **2**）、器物状态 **8**；版本以代码为准。内容包是原 37 份定义的 v1 快照，部分动作等规则仍直接读取项目文件。历史输入及退役边界见[兼容政策](../engineering/compatibility.md)，真实 fixture 保持只读。
- 游戏代码起点 `bbd4303eb2ae477015dd1d9a40b170562c40a4d8`；分支与未提交文件快照见[分支状态](branches.md)。新环境缓存、温度状态及两份测试的四处工作区改动未提交、未验，不能用已提交代码的证据背书。

## 通用对象与空间首包

代码 `98a65663e325d2a56279fcf99af2c4d991e25a81` 在独立检出完成一次完整check：**249组、97864断言、0失败**，包含来源接口、空间快照和原项目回归；不含四处环境WIP。一次原生Sol/custom审查的占地缩窄问题已窄修并定向通过。合成512²索引和真实两区接口测量单独列于 [QA](../qa/20261105_world_object_contract.md)，不代表完整大世界/实时索引已完成。最终文档head的远端CI未主动等候。

## 生命周期与动作包

主代码 `c529c96910a0ef07af5e6d720bd848f395c4fed8` 及审查窄修 `b78f3af607c3b8c798411f4945de123d1d0ebf30` 接入受控实物、地面位置、材料和共同耗时搬运。后者精确SHA在独立检出完成完整check：**254组、98467断言、0失败**，1127.369秒且无ERROR/SCRIPT ERROR。已有262144真实静态物品的同进程内存序列化/独立候选恢复、普通Main RTX3060帧时、小会话双进程和双聚落证据，范围见[QA](../qa/20261105_object_lifecycle.md)；不将它们合称满密度跨进程重开或大规模NPC通过。前一head `d0bcf3734b4b6742fe6cee9c4d19467520a9ee14` 的[CI41982168735](https://github.com/fewnfds/reol/actions/runs/41982168735)在本次真实提交检查点核为completed/success。

第一阶段A–E的联合出口已按声明范围补齐，见[最终验收](../qa/20261105_world_foundation_exit.md)：同一普通Main实际离返后在途保存并由新进程恢复、512²真实物品落盘/候选恢复与256件批量变更、满格普通场景1800帧、有限动态体恢复。受测游戏逻辑仍为b78，后续改动仅基准和文档。单3060呈现p99 8.618ms；满密度候选恢复32.685s、峰值工作集4.82GiB，是后续优化依据。16GB整机仍是目标，未在真实16GB主机验收；动态只证1/4/8大型身体。

后续基准/文档提交 `06067d300a6c0158a1f602458afca2ac80a68598` 的 [CI41994818299](https://github.com/fewnfds/reol/actions/runs/41994818299) 在环境首轮方案的真实提交检查点一次核为completed/success，headSha完全匹配。该证据仍不包含四份本机环境WIP。

## A1地面环境来源

代码 `8bf7aa2a012af393fbc1b96fea6220aa18825833` 提供显式schema/digest、真实ground实物/材料堆投影和有界局部基础目标查询；不改变普通内容包和schema51/区域42。定向147断言/0失败，Sol/custom原生只读审查无可行动问题；真实512²地面物品复测局部查询p99 11.619ms、峰值进程工作集约1.39GiB。同一精确SHA独立检出完整check通过：**255组、98618断言、0失败**，1094.512秒，无ERROR/SCRIPT ERROR。[CI42008084331](https://github.com/fewnfds/reol/actions/runs/42008084331)在随后A2a方案的真实文档提交检查点核为completed/success，完整headSha匹配；没有轮询或重复本机完整回归。支持范围、源码哈希和测量口径见[来源QA](../qa/20261105_environment_source_bindings.md)；不涵盖响应残留、每帧全图更新或Main接管。

## 最近有效证据

### A2a真实来源缓存

代码`4c1a2e9cd64ed89948f374008f6bcd9c35aa1b23`及一次Sol/custom审查窄修`3636dc37ea498fa1f57c1d970fca6e50289aff93`接通真实地面原物的预算装配、16×16基础目标缓存、通知前失效和epoch/所有者重绑。修复SHA独立检出完整check：**257组、99000断言、0失败**，1291.078秒，无ERROR/SCRIPT ERROR；原四份环境WIP未混入。定向1685断言0失败；512²真实262144来源全域冷建约19.26秒分片累计、advance p99约2.06ms，1024热读p95约10ms，未达初始5ms目标；离线进程峰工作集约2.2GiB，不是整款游戏容量或动态场FPS。证据见[缓存QA](../qa/20261105_environment_ground_cache.md)。

首代码SHA的[CI42025370605](https://github.com/fewnfds/reol/actions/runs/42025370605)在收尾实际提交检查点核completed/success；修复SHA的[CI42026400068](https://github.com/fewnfds/reol/actions/runs/42026400068)最后观测in_progress，尚待下次提交核验。主验收使用上述本机精确SHA完整check，不能把首提交CI结果当修复SHA绿色。普通Main、实际环境响应、移动携源与GPU未由该服务接管。

| SHA、范围或案例 | 已有证据 | 不覆盖 |
|---|---|---|
| `bbd4303eb2ae477015dd1d9a40b170562c40a4d8` 的共同时间修复 | 普通 Main 先结算世界再发布时间；定向回归含暂停、真实在途与完全停开接续，细节见[共同时间QA](../qa/20261105_clock_world_commit.md)。 | [CI 41968678863](https://github.com/fewnfds/reol/actions/runs/41968678863) 于本轮真实提交检查点核为 `completed/success`，精确 headSha 为左列完整 SHA；不表示新环境场已接入。 |
| `923a95b18c8f127819d48e6397896125f9942d01` | [CI 41963564648](https://github.com/fewnfds/reol/actions/runs/41963564648) 曾核 `completed/success`，覆盖此前 packed/bulk。 | 不覆盖后来的源场联合候选和共同时间修复。 |
| `0920d28d50124cc561ad465d89f62360b84d2fd0` | [CI 41966563221](https://github.com/fewnfds/reol/actions/runs/41966563221) 本轮真实提交检查点核为 `completed/success`。 | 只覆盖该 SHA，不覆盖后续修改或未提交 WIP。 |
| 源场/温度联合候选 | 定向与独立两进程证据见[源场与温度](../qa/20261105_source_temperature_transition.md)。 | 仅隔离候选；真实原物、普通 Main、动态密集规模和完整房间未验。 |
| GPU/CPU 场服务 | 有真实 GPU 逐格对照与局部规模测量，见[计算加速](../qa/20261105_field_compute_acceleration.md)。 | 不能把静态或局部样本当完整世界容量、FPS 或玩家可用开关。 |

更早按准确 SHA 的成功、失败和修复记录保留在[历史分卷](../qa/baseline-history/README.md)；较早绿色、模型审查、截图或定向断言都不能代替目标 SHA 的完整回归。

## 主要边界

普通 Main 仍使用旧 Q 冷热模型。新五行/冷热源场、实际温度和共同时间尚未与真实物件、人体/植物、房间和普通存档完成联合接管；临时隔离原型不是玩家可用功能。声明的 512²、1024²、2048² 密集实体/场源、动态改造、长期远区和存读规模尚未完成联合性能验收。完整 45–60 分钟切片、正式美术与 Windows 独立发布仍未验收。

历史成绩按所记硬件、数据量与路径解读，不外推所有地图或未来代码。工具版本与配置见[工具套件](../engineering/tooling/setup.md)，基线文档不复制工具清单。
