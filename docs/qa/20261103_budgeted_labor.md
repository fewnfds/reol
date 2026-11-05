# P1-f 有预算劳动与实际领薪验收

2026-11-03。规格见[预算劳动](../archive/specifications/budgeted_labor.md)，当前总检查见[BASELINE](../status/baseline.md)。原完整游戏Goal保持active。

## 实际范围

C承接原送柴/挑水，现任付款权和本人缺料认识分别复核；原公库先将真实现金移入唯一专款。原actor.active完成预约、取公料、路线与交付，原保管责任不变。中断可续原批，未交付可放弃/到期，满库退款保留专款。交付产生待验工资，不发贡献凭据；C当面找现任，再由原服务走到功德堂耗时验收，实际付款。签约者/付款者分开，换任或满包失败不丢钱。

根26/区域23/服务5/预算劳动1，村落仍4。v25显式迁空新合同，不补钱货/工资/历史。候选联合核验资金/原交付/社会事件/零贡献与验收引用，成功后才替换世界。

## 规则与运行验证

`test_budgeted_labor.gd`及`test_budgeted_labor_runtime.gd`覆盖无钱/权限/所知需求、重复承接/申领、同消息后的承诺量、原资金守恒、原公物与停工/普通入口续做、期限/满库退款、NPC相同API、验收途中换任/满包、113ms和稀疏推进/近远一致、联合坏候选、劳动中/验收中存读、旧v25迁空及两份真实v26在新主场景相同未来。最终完整检查统一记BASELINE；此前定向probe为410断言/0失败。没有为此重写旧fixture。

## 正常游戏流程与真实档

未注入钱货，未关闭NPC自主，未瞬移；普通游戏档未覆盖。新杂役开局钱6，鼠标C买1现饭后钱4、公库2。管事自己行走并亲见缺柴，180050ms实际C承接labor:1，公库0/专款2/行囊钱4。原action:7实际取公柴3；182550ms鼠标停止后paused，柴和专款保留。鼠标续做原action:8，没有再领柴或留工钱。

| 来源 | 保存时状态 | 完整停开后同一未来 |
|---|---|---|
| `session_v26.json` | 183551ms原action:8中，公柴3/专款2/钱4 | 再500000ms到683551ms，485050ms真实交付、payable；全联合JSON逐字一致，97480字节/散列3723418476 |
| `wage_claim_v26.json` | 684552ms原service:job:4验收途中，专款2/钱4 | 再180000ms到864552ms，804841ms实际付款；全联合JSON逐字一致，104935字节/散列2052718775 |

最终钱6/专款0/贡献0。阿禾正在原温石研究时autonomous暂为false，原器物job保存previous_autonomous=true；其余日常继续，不能误写成测试关闭自主。

第一档原样复制`user://qa_budgeted_labor_work_20261103.json`，140255字节，SHA256 `fb4e849222f1e738a5c9140012db5392ad74991c7986617cd2287fd1a167d360`。第二档来自`user://qa_budgeted_labor_claim_20261103.json`，161584字节，SHA256 `1ebf265690d16bea20290261292abbe20232b74d8f7a266e79a83fa731350c19`。另存已领钱的`user://qa_budgeted_labor_paid_20261103.json`，不用它覆盖普通档。

原始对照位于`logs/budgeted-labor-future-20261103.json`、`budgeted-labor-restarted-20261103.json`、`budgeted-claim-future-20261103.json`、`budgeted-claim-restarted-20261103.json`。鼠标过程截图`logs/budgeted-labor-funded-20261103.png`、`budgeted-labor-paid-20261103.png`。

## 文字缺失与渲染对照

前两张D3D12截图存在间歇文字片段消失：Label.text本身完整，界面和世界字样都会发生。显式SystemFont切换仅暂时恢复，重开/读档仍复现，所有该字体实验代码已撤回。一次临时FontFile.clear_cache诊断引发字体RID错误，未写入产品代码，已完整停开恢复；旧运行日志保留。一次临时eval空格/制表符混用造成debugger break，亦已停开重置。

通过编辑器移除项目Windows D3D12覆盖，使用Godot默认Vulkan；不改用户全局。run143/144/145均实测Vulkan/Forward+，完整停开、六次重复读验收档/推进/切C和工钱页未再见缺字。最终run145启动当前错误为空，工钱页文字完整，`logs/budgeted-labor-vulkan-reloads-20261103.png`、`budgeted-labor-vulkan-restarted-20261103.png`、`budgeted-labor-vulkan-request-20261103.png`。Vulkan续算与原D3D12验收未来逐字相同，104935字节/散列2052718775，原样对照`logs/budgeted-claim-vulkan-20261103.json`。

同机RTX3060/1280×720独立运行原`tools/qa/profile_game.gd`，真实v11、34区块、暖机1200ms/各120帧；配置仍VSync关/最高120。报告`logs/profile_source_v11_vulkan.json`及log，exit0：

| 当前小世界 | 中位 / p95 |
|---|---|
| 完整静态 | 8.347 / 8.403ms |
| 实际1×生活 | 8.338 / 8.410ms |
| 隐藏地形 | 8.354 / 8.397ms |
| 空主场景 | 8.342 / 8.445ms |

先前D3D12同类1×为8.340/8.381ms；这是当前硬件/小世界的显示回归，不是速度提升或发布规模验收，也不证明所有显卡的根因已消除。该包当时保留Vulkan项目默认、未加字体补丁。后续有限交谈的图像再次有缺少元素，同静止画面8份直接PNG又完整一致，证据不足以锁定字体/后端或截图路径；现已恢复原D3D12，调查未结案，见[后续记录](20261103_capability_conversation.md)。

## 未交付

两项机构现金差事只验证了有限雇佣链；NPC自动求职/招工、私人雇主/代工、工资协商、政治赖账/继任、完整组织与市场仍待做。无永久伤亡/医疗或完整人生接续；原完整游戏Goal尚未完成。
