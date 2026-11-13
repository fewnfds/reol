# 当前接续

更新：2026-11-13。人物/装备/格子背包及本次流程整理均已完成。性能工具改为历史同负载对照；开发循环已收敛为五步，持久文档采用三问归属检查，并补充了OpenAI agent-first参考。短验证/实际工具窗口通过。游戏运行代码未改，原试玩包仍有效。

## 找当前信息

- 能玩什么、键位和缺口：[FEATURES](features.md)。
- 正式构建与已接受测量：[BASELINE](baseline.md)；数值原件：[performance.json](performance.json)。
- 状态owner与调用边界：[架构](../engineering/architecture.md)；实施方向：[主计划](../plans/foundation-priorities.md)。
- 每轮怎样开发/验证/交接：[开发循环](../engineering/workflow/testing.md)；工具语法：[usage](../engineering/tooling/usage.md)。

没有自动续跑的旧优化任务；后续从用户试玩反馈选题。新AI只需补本次缺少的信息，不重读全部历史。可选本机顾问入口仍由根AGENTS发现。

## 受保护内容

- 保留分支codex/field-contest及已有工作分支、stash 424f956d280fb390d17e1f6dd879f3614b51a430。
- 用户存档、凭据、原始素材与第三方addon；本机问答、日志和构建产物不入库。
