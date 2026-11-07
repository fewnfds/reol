# 当前接续

2026-11-07：**顶层稀疏执行框架及普通环境/健康两域接入已完成本机验收和一次审查。** Goal收口；不扩demo、自动迁完全部旧系统或合并main。范围见[实施规格](../plans/runtime-efficiency/implementation.md)与[QA](../qa/20261107_sparse_execution.md)。

## 当前主线与可用范围

根项目在`codex/sparse-world-execution`，从`main`的`eff27a7`起步；先前未提交文档已保全为`45d2fa5`。主线受检代码`6137481a07ec98b372e32ca857e546f1e1b07ee1`，收尾集成点`ffe7e8c705d2d7259dfb77dcfba3dd0a64c9c61c`已在本地/远端main。旧争环分支未合入。本包改动未获新验收前不继承旧绿灯，原功能与采用版本查[FEATURES](features.md)、[BASELINE](baseline.md)。

普通Main已用唯一室外冷热/五行场，原身体/器物/库存/账本和共同时间仍由原所有者持有；真实生成/移除/位置/材料、设备启停和有限容量经来源事务提交。人体/野药读取同一温度，背景与实际残留、进行中动作进入普通联合存档。当前根52/区域43/bundle2；旧根1–51明确拒绝并保留原档，不同时运行两套环境。

## 验证与局限

- 准确代码SHA本机完整check：**244组、124778断言、0失败**，无SCRIPT ERROR/ERROR；1174源文件指纹前后不变。
- 同SHA普通Main两个独立进程181000ms在途存档→完全退出→恢复至相同184001ms未来；原物、材料、两地离返和环境摘要一致。
- 同SHA单RTX3060/D3D12的普通F8画面和600帧稀疏联合负载通过。推进p95/p99为4.776/6.056ms，帧间隔p95/p99为19.054/31.300ms；单生成/材料变更仍约0.22秒同步卡顿。不是满密度或16GB整机所有系统通过证明。
- 一次Sol/custom主要静态审查已完成，3项发现均修复；无需重复审查或完整回归。
- 最终代码[CI42337874837](https://github.com/fewnfds/reol/actions/runs/42337874837)在本次真实调查文档提交检查点核为completed/success，完整headSha6137481一致；本包已有准确SHA本机及CI证据，不重复测试，不轮询。

完整房温/隔热、携物整体辐射/尾迹/遮掩、GPU玩家开关、大规模人口和后续战斗/修炼/组织玩法未在本包实现。墙门顶已有围合/通行/遮挡/遮雨，不阻隔当前冷热/五行；不宣称完整游戏或45–60分钟切片完成。

## 原草稿与证据

四原WIP已核字节后保存命名stash`424f956d280fb390d17e1f6dd879f3614b51a430`（`preserved-env-drafts-before-world-engine-merge-20261107`），原字节备份/清单在`logs/world_engine_finish/protected-wip/`；stash再核与清单及备份相同，**不自动应用到新主线**。采用前按当前接口人工比对，不能覆盖已验实现。

本包95份日志/JSON/截图/指纹已保全到`logs/world_engine_finish/validation-artifacts/`，含失败证据与evidence-sha256.json。快进/远端核验见`logs/world_engine_finish/merge-result.json`。临时工作树的保留/移除状态查[分支快照](branches.md)，不要在临时检出继续玩法开发。

## 用户最新工作流约束

禁止为了播报进度定时读testlog、数PASS或让模型充当计时器；AGENTS.md早已明确，之前反复扫描是执行错误。只在进程结束取终态，失败/超时或用户要求才读中间输出；没有宿主自动唤醒已结束聊天的回调。

存档是[当前世界快照](../engineering/architecture/04-persistence.md)，不是操作历史重放。已调研Godot内置与两个插件，未安装插件或重写格式。用户接受暂停保存；当前是同步save_game并在未结算时拒绝，尚未自动编排暂停/结步/恢复，留待后续有界任务，不扩作本包前置。

单次来源变更已完成[成本调查](../qa/20261107_source_change_review.md)：普通Main透明代理短测石板224.152ms/木料220.514ms，约83%在四整块1024格基础场重算，显式can_commit三次合计0.015ms。临时剖析脚本/原日志只在logs/source_change_review，原生产算法不变。

## 最新方案与停点

用户要求扩大到顶层框架：按实体实际拥有的可选能力执行，同时复核其他领域同类问题，禁止只对具名物品打补丁。已交付[统一运行效率方案](../plans/runtime-efficiency/README.md)，拆为执行合同、代码审计与实施验收；已接入计划入口及AGENTS稳定规则。

统一入口是“定义编译→能力成员→实际参与→变脏/到期工作→局部/可见投影”。除已测环境路径外，人物自主/健康/衣物、空间容器候选、显示和长期历史均仅登记静态增长风险，不冒充已测热点。建议A先接所有profile的能力参与和环境选择性执行，再讨论B人物、C空间/呈现、D剩余历史/复制；不另造全量ECS、第二实体真值或时钟。

最新授权覆盖上述方案的“只写文档”停点：Goal active，doctor核Godot4.7.2，通用索引、普通环境和健康接入首版已写完。定向1198断言0失败；普通Main相同来源操作224/221ms→8.081/7.173ms（各一次headless CPU短样本）。证据与限制见[本包QA](../qa/20261107_sparse_execution.md)。

受检代码`ee3504d3c313aa07ac4e87caec3bd39488c725e3`的唯一完整check已终态通过：248组、124980断言、0失败；一次Sol/custom静态审查已终态无发现。原sessions96715/66478均已结束，不再恢复或重复运行；日志`logs/sparse-execution/full-check-console.log`、`logs/check-test-20261107-133850.log`及`logs/sparse-execution/review-ee3504d.log`。后续仅收口文档，代码差异为空。本包新推送CI未核，不立即查询/等待，下一真实提交检查点再核；没有本地验证正在运行。不自动展开全部A–D迁移或新玩法。
