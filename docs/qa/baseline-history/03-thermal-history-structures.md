# 验证基线历史分卷 03

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../status/baseline.md)。

### C1c-1c 施工与热场的原子拒绝边界

普通建成先复用原库存`can_consume`只读核成本；拆墙先推导全部将塌屋顶，逐原容器核余料ID/收据冲突和容量，再让热场按完整改变格预检当前物理时刻。拒绝不扣完工料、不发余料、不移除支撑或半个屋顶，不发送成功信号；已做工时与原材料保留并释放劳作。所有检查后才一次before、提交原物/结构、统一重索引、一次after及通知。原`before_topology_change`返回真实结算成功；不改变格式/积分或解除512格限制。

最终库存/热/拓扑/真实施工/热建造/呈现通知6组862项0失败，4.663秒/230469632B工作集（`logs/thermal-topology-focus-fixed.json`）；导入5.825秒/1004343296B、无脚本错误，结构检查201文档/401脚本0错误。首跑因typed Array的三元空数组丢类型而反复触发运行错误，30秒受限中止；已改为显式分支赋值，保留断言后复验通过（首错`logs/thermal-topology-focus.json`），未放宽门禁。

原生复用[结构QA](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/structure_capture.gd)的隔离输出副本，真实新局搬料建7处墙门，1344762ms保存并完全退出；独立普通加载完整摘要同为`3460d373f53cc711d57ae497b7fdfe2eaf644379928960bf19524669b2a70fcc`。重启后原人物不动开/关门，真实遮挡与Fog目标可见性随完成边界false→true→false，1600×900的closed/open截图已观察。日志`logs/thermal-topology-native-safe-{write,read}.json`及`logs/thermal_topology_structure_safe_{write,read}.json`，截图同前缀。两进程13.575/8.897秒，工作集494235648/480710656B，采样私有699224064/703131648B，均30秒/1GiB有界；这不是容量或FPS证明。首试旧QA自动选址包含现受保护道路，建墙被正确拒绝；已将QA改为选择当前规则下合法完整工地（仍由原register_site/build验证），未关道路保护。入库QA各函数与实际通过的隔离副本逐值核一致，只差输出名/函数排列，旧证据未覆盖。

本包最终SHA完整回归待CI；此提交检查点准确4394dfb/run41922985281仅发现pending，不等待。首次手输非Git SHA的空结果不算目标查询证据，随后从Git取值纠正发现一次；后续沿登记run接续，不按时轮询。

代码`ed5193e2dbda2c3e3a6bca17a05e89c625d1e58f`的一次Sol/custom显式read-only原生审查124.534秒/退出0，无可操作发现，涵盖库存幂等、整组塌顶、热同步及事务顺序；仅核已有证据，未启动引擎/测试/CI或改文件。日志`logs/reviews/<SHA>.explicit-sol.log`及`.explicit-sol.summary.json`，完整最终SHA回归仍待CI。

### C1c-1b 热场历史覆盖与样本解耦

普通完整热schema现以`SimThermalHistory`从原receipt/设备启用推导覆盖和首次分配，保留旧转换仅由pulse证明的同毫秒上下界；`SimThermalSample`以独立历史Q/累计账与原气候底量核采样，不读取当前cells/flows。完整候选继续认证原事件/器物余额、严格覆盖全部当前Q及重建冻结段；删当前格或改分配/底量仍拒绝。`has_visible_offsets(true)`从已验历史键读取坐标。不新增格式、余额、回收或移动热，当前仍512活格。

最终新组167项/0失败，2.461秒、峰值工作集237035520B（`logs/thermal-history-focus-corrected.json`）；原热规则/设备/人体/结构/精确分组712项/0失败，6.641秒、227483648B（`logs/thermal-history-existing.json`）。旧导入组合在30秒预算于最后植物归档组被中止：前六组（absolute、thermal_import、device_migration、heat_archive、heat_migration、herb_environment）均完成且无FAIL/脚本错误，但未输出总断言，不能称组合整跑通过（`logs/thermal-history-legacy.json`）；只将未完成的植物归档单独验证，22项/0失败、20.219秒/430358528B（`logs/thermal-history-herb-archive.json`）。新增边界首跑167项有1条测试误把完整schema的几何查询计数当世界变更；已保留无副作用断言并对完整验证排除诊断计数，纠正后通过，未改产品校验。

沿原普通Main/UI的真实学习启用，在120173ms保存进行中放热段；写进程完全退出，读进程恢复后再推进35000ms，原器物扣量/热流/人体等完整检查点与未来摘要均一致。检查点`0a5c50a7305a1135ae9a8404478a9bff10fcae22a4ed62a3155eb973598209d0`，未来`27818f070b589e11c5c053f450ed4b0eca47587465abc1f30139b04f1af4ae02`。复用原QA脚本的本地改名副本，未覆盖旧证据；`logs/thermal-history-native-{write,read}.json`及`logs/thermal_history_{write,read,expected}.json`，原生1600×900的`logs/thermal_history_read_future.png`已观察。两进程各6.98秒，峰值工作集499519488/447631360B；峰值采样私有646840320/669290496B。单进程仍30秒/1GiB预算。

同机i5-13600KF/20逻辑核、34104020992B内存、Godot4.7.2 debug无头，512格组件/28笔合成有限来源、真实默认气候、40次×1秒推进及3次完整JSON恢复、不同分片未来一致。推进p95/p99为15.316/16.158ms，恢复p95为31.848ms（仅3样本），总进程2.452秒/209219584B；报告`logs/thermal-history-512.json`。这是既有上限的组件验证（来源脉冲100倍），不是真实器物/全世界/FPS、扩容或长期性能证明。完整CI仍待本包最终SHA，不本机双跑全套；原fixture未改。

代码`1b8cc633f767eff1b27148654e258abad7fb359e`的一次Sol/custom显式read-only原生审查127.185秒/退出0，无可操作发现；审查器核现有证据，未启动引擎/测试/CI或修改文件。日志`logs/reviews/<SHA>.explicit-sol.log`与`.explicit-sol.summary.json`，不重复整包审查。最终导入5.832秒/1007349760B工作集、无引擎错误；完整SHA回归仍待CI。

恢复世界引擎后集中修复旧CI缺陷：课程的方法集合不再依赖内容字典键顺序，仍严格拒绝缺项/多项/重复/替换，原课程历史顺序不改，新课程稳定排序。其余为测试接缝：显式选墙而非菜单首项、修改真实内容包而非只改运行policy、合成地图显式独立工厂、更新旅程校验参数及单/双域装配断言。原历史fixture未改写。

本机定向：施工/交割2组79断言0失败（`logs/recovery-construction-exchange.log`）；存读9组首跑1048断言中2条旧单域装配断言失败，其余通过，修正后仅复验受影响组并加装配组，3组503断言0失败（`logs/recovery-session-recheck.log`，首跑`logs/recovery-session-target.log`）。覆盖真实v35/v36/v39继续、课堂集合损坏、在途交割、墙体通行、候选隔离及单/双域入口；最终SHA完整回归仍待CI，不把定向相加冒称全套通过。

恢复包`306157af5b4d5c396cb6ca2f36a70d0b7709da94`已推送，原生Sol审查无可操作缺陷；日志`logs/reviews/<SHA>.explicit-sol.log`。B0b提交检查点核对[CI 41829419102](https://github.com/fewnfds/reol/actions/runs/41829419102)，完整SHA同306157a，终态completed/cancelled，不能当通过。B0a完整SHA`3a2b021d632f963a09c0ce796b971f9beef03167`已审查无可操作缺陷并推送；同检查点一次发现[CI 41831613258](https://github.com/fewnfds/reol/actions/runs/41831613258)为in_progress，留到下次实际提交核结果，不启用等待器。
