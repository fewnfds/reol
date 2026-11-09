# 当前接续

2026-11-09：用户授权决定并实现通用SL模块，分支`codex/save-load-framework`基于main `f63844b3cd18f92624f58de3749b1fbbcdd32fdd`。当前准备产品提交与一次原生静态审查，没有新Goal；不启动植物等新领域。

## 当前实现

采用Godot FileAccess/JSON与原`SimSaveStore`，不引入SaveKit/I,Voyager。`SimSaveRegistry`统一数据参与者capture/stage/check/install与库存范围；`SimWorldSaveDomains`成为唯一世界存档目录，消除中央逐域new/restore/bind链。`SimSaveSession`统一保存/候选加载操作；UI/F5沿保存屏障停止新增时间，按原预算结清已受理工作后写档，以完成回执报告成功，保留玩家暂停、未启动欠算与未来等待目标。失败/超时/取消释放屏障；严格同步API仍拒绝半步。

根53/区域44与领域wire记录保持。候选在独立世界校验，不补发开局事实；`local_actions.json`、`workplaces.json`、`sparring.json`规则来源闭包仍归主计划前置，未借本包扩成所有领域重写。公共接口和成熟方案取舍见[存读合同](../engineering/architecture/04-persistence.md)。

## 验证与待办

最终定向保存协调/登记/真实clock三组188检查，包装器退出0；此前区域坏档/current roundtrip、独立工厂、原活动所有权和双区运行存读定向亦通过，详细受检范围将在QA登记。真实Main预算1保存121帧完成；同进程与完全停开checkpoint及250ms未来一致，原生截图已查看（本机实际5060Ti，仅画面证据，不是3060性能验收）。当前最终版本还须一次原生静态审查、推送及对应SHA完整CI，不能以定向代替全量。

下一步提交产品→静态审查→修复有效问题并推送，随后现有证据与状态文档收尾；不按时间轮询CI。代码或测试变化后按影响验证。

## 保护与CI

旧`codex/field-contest` = `4e17c5c165cf8fca9ef884a111aa1c3ca35f445f`与命名stash `424f956d280fb390d17e1f6dd879f3614b51a430`保持隔离。产品提交准备点一次找到main起点f63844b的[CI42544116843](https://github.com/fewnfds/reol/actions/runs/42544116843)为completed/success，完整SHA吻合；这不代替本包CI。
